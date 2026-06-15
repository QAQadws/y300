import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_parsing_rule.dart';
import 'package:y300/features/novel/domain/services/novel_same_thread_catalog_extractor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

/// Builds a refresh plan from thread pages by applying small parsing rules.
///
/// The service is intentionally only an orchestrator: DOM normalization lives in
/// [ForumPostDomExtractor], while title/cover/intro decisions live in
/// [NovelParsingRule] implementations. New parser capabilities should normally
/// be added as rules instead of expanding this loop.
class NovelEpisodeDiscoveryService {
  const NovelEpisodeDiscoveryService({
    List<NovelParsingRule>? rules,
    ForumPostDomExtractor? domExtractor,
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
    NovelSameThreadCatalogExtractor? catalogExtractor,
  }) : _rules = rules ?? NovelParsingRules.defaults,
       _domExtractor = domExtractor ?? const ForumPostDomExtractor(),
       _imageSourcePipeline = imageSourcePipeline,
       _catalogExtractor = catalogExtractor ?? const NovelSameThreadCatalogExtractor();

  final List<NovelParsingRule> _rules;
  final ForumPostDomExtractor _domExtractor;
  final ForumImageSourcePipeline _imageSourcePipeline;
  final NovelSameThreadCatalogExtractor _catalogExtractor;

  NovelRefreshPlan buildPlan({
    required String novelId,
    required List<ThreadDetailData> pages,
    NovelDiscoveryOptions options = NovelDiscoveryOptions.defaults,
  }) {
    if (pages.isEmpty) {
      throw StateError('线程页面为空，无法生成章节计划');
    }

    final firstPage = pages.first;
    final opAuthorId = firstPage.posts.isEmpty ? '' : firstPage.posts.first.authorId;
    final builder = _NovelRefreshPlanBuilder(
      firstPage: firstPage,
      pageCount: pages.length,
      orderIndexOffset: options.orderIndexOffset,
      suppressFirstChapterMetadata: options.skipFirstChapterMetadata,
    );
    final allPosts = _flattenPosts(pages);
    final postsByPid = <String, _PostOnPage>{
      for (final item in allPosts) item.post.pid: item,
    };
    final firstPagePosts = pages.first.posts;
    final catalogEntries = options.skipCatalogExtraction
        ? const <NovelCatalogEntry>[]
        : _catalogExtractor.extract(
            threadTid: firstPage.tid,
            opAuthorId: opAuthorId,
            posts: firstPagePosts,
          );

    if (catalogEntries.isNotEmpty) {
      _collectCatalogMeta(
        novelId: novelId,
        opAuthorId: opAuthorId,
        posts: allPosts,
        builder: builder,
      );
      for (final entry in catalogEntries) {
        final source = postsByPid[entry.pid];
        final sourcePost = source?.post;
        final sourcePage = source?.page;
        final plainText = sourcePost == null ? '' : _domExtractor.extractPlainText(sourcePost.message);
        final paragraphs = sourcePost == null
            ? const <String>[]
            : _domExtractor.extractParagraphTexts(sourcePost.message);
        final imageUrls = sourcePost == null
            ? const <String>[]
            : _collectImageUrls(sourcePost);
        builder.addInlineImages(imageUrls);
        builder.addEpisode(
          NovelEpisodeDraft(
            episodeId: '$novelId:${entry.pid}',
            novelId: novelId,
            sourceTid: firstPage.tid,
            sourcePid: entry.pid,
            sourcePage: sourcePage?.currentPage ?? 0,
            episodeTitle: entry.title,
            orderIndex: builder.episodeCount,
            datelineText: sourcePost?.dateline ?? '',
            rawHtml: sourcePost?.message ?? '',
            plainText: plainText,
            paragraphs: paragraphs,
            imageUrls: imageUrls,
          ),
        );
      }
      builder.addSignal(
        NovelParsingSignal(stage: 'catalog', message: 'same-thread pid catalog entries=${catalogEntries.length}'),
      );
      return builder.build();
    }

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      for (final post in page.posts) {
        final context = NovelParsingContext(
          novelId: novelId,
          page: page,
          post: post,
          opAuthorId: opAuthorId,
          domExtractor: _domExtractor,
          currentOrderIndex: builder.episodeCount,
          plainText: _domExtractor.extractPlainText(post.message),
          paragraphs: _domExtractor.extractParagraphTexts(post.message),
          imageUrls: _collectImageUrls(post),
          headingTexts: _domExtractor.extractHeadingTexts(post.message),
        );
        builder.addPostStats(
          totalAnchors: _domExtractor.extractAnchors(post.message).length,
          isOpPost: opAuthorId.isEmpty || post.authorId == opAuthorId,
        );

        final result = _applyRules(context);
        builder.acceptMeta(result);
        if (result.rejectPost || !result.acceptAsEpisode) {
          continue;
        }

        final pageNumber = page.currentPage > 0 ? page.currentPage : (pageIndex + 1);
        builder.addEpisode(
          NovelEpisodeDraft(
            episodeId: '$novelId:${post.pid}',
            novelId: novelId,
            sourceTid: page.tid,
            sourcePid: post.pid,
            sourcePage: pageNumber,
            episodeTitle: result.titleCandidate ?? '第${builder.episodeCount + 1}节（PID:${post.pid}）',
            orderIndex: builder.episodeCount,
            datelineText: post.dateline,
            rawHtml: post.message,
            plainText: context.plainText,
            paragraphs: result.paragraphs ?? context.paragraphs,
            imageUrls: result.imageUrls,
          ),
        );
      }
    }

    return builder.build();
  }

  List<_PostOnPage> _flattenPosts(List<ThreadDetailData> pages) {
    return <_PostOnPage>[
      for (final page in pages)
        for (final post in page.posts) _PostOnPage(page: page, post: post),
    ]..sort((a, b) {
        final pageCompare = a.page.currentPage.compareTo(b.page.currentPage);
        if (pageCompare != 0) {
          return pageCompare;
        }
        return a.post.number.compareTo(b.post.number);
      });
  }

  void _collectCatalogMeta({
    required String novelId,
    required String opAuthorId,
    required List<_PostOnPage> posts,
    required _NovelRefreshPlanBuilder builder,
  }) {
    for (final item in posts) {
      final page = item.page;
      final post = item.post;
      final isOpPost = opAuthorId.isEmpty || post.authorId == opAuthorId;
      builder.addPostStats(
        totalAnchors: _domExtractor.extractAnchors(post.message).length,
        isOpPost: isOpPost,
      );
      if (!isOpPost) {
        continue;
      }
      final context = NovelParsingContext(
        novelId: novelId,
        page: page,
        post: post,
        opAuthorId: opAuthorId,
        domExtractor: _domExtractor,
        currentOrderIndex: builder.episodeCount,
        plainText: _domExtractor.extractPlainText(post.message),
        paragraphs: _domExtractor.extractParagraphTexts(post.message),
        imageUrls: _collectImageUrls(post),
        headingTexts: _domExtractor.extractHeadingTexts(post.message),
      );
      final result = _applyRules(context);
      builder.acceptMeta(result);
    }
  }

  List<String> _collectImageUrls(ThreadPost post) {
    return _imageSourcePipeline
        .collectFromPost(post)
        .map((source) => source.normalizedUrl)
        .toList(growable: false);
  }

  NovelRuleResult _applyRules(NovelParsingContext context) {
    var merged = NovelRuleResult.empty;
    for (final rule in _rules) {
      merged = merged.merge(rule.apply(context));
      if (merged.rejectPost) {
        break;
      }
    }
    return merged;
  }
}

class _NovelRefreshPlanBuilder {
  _NovelRefreshPlanBuilder({
    required this.firstPage,
    required this.pageCount,
    this.orderIndexOffset = 0,
    this.suppressFirstChapterMetadata = false,
  });

  final ThreadDetailData firstPage;
  final int pageCount;

  /// 新章节的起始 orderIndex（含）。
  ///
  /// `episodeCount` 投影成 `_episodes.length + orderIndexOffset`，让规则收到的
  /// `currentOrderIndex` 与最终写入的 `NovelEpisodeDraft.orderIndex` 都自动平移。
  final int orderIndexOffset;

  /// 不收 cover/intro 信号 —— 增量刷新场景下显式压制。
  final bool suppressFirstChapterMetadata;

  final List<NovelEpisodeDraft> _episodes = <NovelEpisodeDraft>[];
  final List<NovelParsingSignal> _signals = <NovelParsingSignal>[];
  final List<String> _inlineImageUrls = <String>[];
  final Set<String> _seenInlineImageUrls = <String>{};
  String? _intro;
  String? _coverImageUrl;
  int _totalAnchors = 0;
  int _totalOpPosts = 0;
  int _fallbackTitleCount = 0;

  int get episodeCount => _episodes.length + orderIndexOffset;

  void addPostStats({
    required int totalAnchors,
    required bool isOpPost,
  }) {
    _totalAnchors += totalAnchors;
    if (isOpPost) {
      _totalOpPosts += 1;
    }
  }

  void acceptMeta(NovelRuleResult result) {
    _signals.addAll(result.signals);
    if (!suppressFirstChapterMetadata) {
      _intro ??= _normalizeNullable(result.intro);
      _coverImageUrl ??= _normalizeNullable(result.coverImageUrl);
    }
    if (result.usedFallbackTitle) {
      _fallbackTitleCount += 1;
    }
    addInlineImages(result.imageUrls);
  }

  void addInlineImages(Iterable<String> imageUrls) {
    for (final imageUrl in imageUrls) {
      if (_seenInlineImageUrls.add(imageUrl)) {
        _inlineImageUrls.add(imageUrl);
      }
    }
  }

  void addSignal(NovelParsingSignal signal) {
    _signals.add(signal);
  }

  void addEpisode(NovelEpisodeDraft draft) {
    _episodes.add(draft);
  }

  NovelRefreshPlan build() {
    return NovelRefreshPlan(
      tid: firstPage.tid,
      subject: firstPage.subject,
      author: firstPage.author,
      episodes: List<NovelEpisodeDraft>.unmodifiable(_episodes),
      intro: _intro,
      coverImageUrl: _coverImageUrl,
      inlineImageUrls: List<String>.unmodifiable(_inlineImageUrls),
      debugInfo: NovelParsingDebugInfo(
        totalAnchors: _totalAnchors,
        totalOpPosts: _totalOpPosts,
        matchedChapterCandidates: _episodes.length,
        fallbackPagesVisited: pageCount,
        signals: <NovelParsingSignal>[
          ..._signals,
          NovelParsingSignal(stage: 'summary', message: 'fallbackTitles=$_fallbackTitleCount'),
        ],
      ),
    );
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _PostOnPage {
  const _PostOnPage({
    required this.page,
    required this.post,
  });

  final ThreadDetailData page;
  final ThreadPost post;
}
