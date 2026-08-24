import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_chapter_eligibility_policy.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_title_candidate_extractor.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_title_policy.dart';
import 'package:y300/features/novel/domain/services/novel_post_attach_html_resolver.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

abstract interface class NovelAuthorPostEpisodeBuilder {
  NovelEpisodeDraft? build({
    required String novelId,
    required String tid,
    required String publisherId,
    required ThreadPost post,
    required int authorFilteredPage,
    required int orderIndex,
  });
}

class DefaultNovelAuthorPostEpisodeBuilder
    implements NovelAuthorPostEpisodeBuilder {
  const DefaultNovelAuthorPostEpisodeBuilder({
    NovelChapterTitlePolicy titlePolicy =
        const FirstMeaningfulSentenceNovelChapterTitlePolicy(),
    ForumPostDomExtractor domExtractor = const ForumPostDomExtractor(),
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
    NovelPostAttachHtmlResolver attachResolver =
        const NovelPostAttachHtmlResolver(),
    NovelChapterTitleCandidateExtractor titleCandidateExtractor =
        const DiscuzNovelChapterTitleCandidateExtractor(),
    NovelAuthorPostChapterEligibilityPolicy chapterEligibilityPolicy =
        const DiscuzNovelAuthorPostChapterEligibilityPolicy(),
  }) : _titlePolicy = titlePolicy,
       _domExtractor = domExtractor,
       _imageSourcePipeline = imageSourcePipeline,
       _attachResolver = attachResolver,
       _titleCandidateExtractor = titleCandidateExtractor,
       _chapterEligibilityPolicy = chapterEligibilityPolicy;

  final NovelChapterTitlePolicy _titlePolicy;
  final ForumPostDomExtractor _domExtractor;
  final ForumImageSourcePipeline _imageSourcePipeline;
  final NovelPostAttachHtmlResolver _attachResolver;
  final NovelChapterTitleCandidateExtractor _titleCandidateExtractor;
  final NovelAuthorPostChapterEligibilityPolicy _chapterEligibilityPolicy;

  static final RegExp _metadataMarker = RegExp(
    r'^[\[【（(]?\s*(简介|簡介|目录|目錄)\s*[\]】）)]?[：:]?$',
  );
  static final RegExp _chapterStart = RegExp(
    r'^(?:第\s*[^\s]{1,12}\s*[章回节節]|序(?:章|言|幕)?|楔子|前言)',
  );

  @override
  NovelEpisodeDraft? build({
    required String novelId,
    required String tid,
    required String publisherId,
    required ThreadPost post,
    required int authorFilteredPage,
    required int orderIndex,
  }) {
    final normalizedPid = post.pid.trim();
    final normalizedPublisherId = publisherId.trim();
    final normalizedTid = tid.trim();
    if (normalizedPid.isEmpty ||
        normalizedTid.isEmpty ||
        normalizedPublisherId.isEmpty ||
        post.authorId.trim() != normalizedPublisherId) {
      return null;
    }

    final rawHtml = _attachResolver.resolve(post);
    if (!_chapterEligibilityPolicy.isEligible(post: post, rawHtml: rawHtml)) {
      return null;
    }
    final plainText = _domExtractor.extractPlainText(rawHtml);
    final paragraphs = _domExtractor.extractParagraphTexts(rawHtml);
    final titleTextUnits = _titleCandidateExtractor.extractTextUnits(rawHtml);
    final imageUrls = _imageSourcePipeline
        .collectFromPost(post)
        .map((source) => source.normalizedUrl)
        .toList(growable: false);
    final titleText = _titleCandidateText(
      post: post,
      paragraphs: titleTextUnits,
      rawHtml: rawHtml,
    );
    final isMetadataOnlyFirstPost = _isMetadataOnlyFirstPost(
      post: post,
      paragraphs: paragraphs,
      rawHtml: rawHtml,
      titleText: titleText,
    );
    if (isMetadataOnlyFirstPost || (plainText.isEmpty && imageUrls.isEmpty)) {
      return null;
    }

    final titleCandidate = _titlePolicy.buildTitle(
      normalizedPlainText: titleText,
      orderIndex: orderIndex,
      pid: normalizedPid,
    );
    // The sync staging schema requires a non-empty title, while presentation
    // owns the localized fallback. Using the source TID as a sentinel keeps
    // that fallback out of the domain/data layer; NovelTextResolver already
    // recognizes a title equal to sourceTid as generated metadata.
    final episodeTitle = titleCandidate.trim().isEmpty
        ? normalizedTid
        : titleCandidate;

    return NovelEpisodeDraft(
      episodeId: '$novelId:$normalizedPid',
      novelId: novelId,
      sourceTid: normalizedTid,
      sourcePid: normalizedPid,
      sourcePage: authorFilteredPage,
      episodeTitle: episodeTitle,
      orderIndex: orderIndex,
      datelineText: post.dateline,
      rawHtml: rawHtml,
      plainText: plainText,
      paragraphs: paragraphs,
      imageUrls: imageUrls,
    );
  }

  String _titleCandidateText({
    required ThreadPost post,
    required List<String> paragraphs,
    required String rawHtml,
  }) {
    final lines = _paragraphLines(paragraphs, rawHtml);
    if (!_isFirstPost(post)) {
      return lines.where((line) => !_metadataMarker.hasMatch(line)).join('\n');
    }

    final introIndex = lines.indexWhere(_isIntroMarker);
    final catalogIndex = lines.indexWhere(_isCatalogMarker);
    final firstMetadataIndex = _firstExistingIndex(introIndex, catalogIndex);
    if (firstMetadataIndex > 0) {
      // 首楼在简介/目录之前常放置作品标题。它是首楼真正的第一条
      // 正文候选，优先级应高于目录尾部尚未链接的 ACT 占位文本。
      return lines.take(firstMetadataIndex).join('\n');
    }
    if (catalogIndex >= 0) {
      final anchorTexts = _domExtractor
          .extractAnchors(rawHtml)
          .map((anchor) => _normalize(anchor.text))
          .where((text) => text.isNotEmpty)
          .toSet();
      final catalogTail = lines.skip(catalogIndex + 1).toList(growable: false);
      final bodyLines = <String>[];
      for (var index = 0; index < catalogTail.length; index++) {
        final line = catalogTail[index];
        if (_metadataMarker.hasMatch(line) ||
            _isAnchorOnlyLine(line, anchorTexts) ||
            _isCatalogGroupHeading(
              lines: catalogTail,
              index: index,
              anchorTexts: anchorTexts,
            )) {
          continue;
        }
        bodyLines.add(line);
      }
      return bodyLines.join('\n');
    }

    if (introIndex >= 0) {
      final chapterIndex = lines.indexWhere(
        (line) => _chapterStart.hasMatch(line),
        introIndex + 1,
      );
      return chapterIndex < 0 ? '' : lines.skip(chapterIndex).join('\n');
    }
    return lines.join('\n');
  }

  int _firstExistingIndex(int left, int right) {
    if (left < 0) {
      return right;
    }
    if (right < 0) {
      return left;
    }
    return left < right ? left : right;
  }

  bool _isMetadataOnlyFirstPost({
    required ThreadPost post,
    required List<String> paragraphs,
    required String rawHtml,
    required String titleText,
  }) {
    if (!_isFirstPost(post)) {
      return false;
    }
    final lines = _paragraphLines(paragraphs, rawHtml);
    final hasMetadataMarker = lines.any(_metadataMarker.hasMatch);
    return hasMetadataMarker && titleText.trim().isEmpty;
  }

  List<String> _paragraphLines(List<String> paragraphs, String rawHtml) {
    final source = paragraphs.isEmpty
        ? <String>[_domExtractor.extractPlainText(rawHtml)]
        : paragraphs;
    return source
        .expand(_splitLines)
        .map(_normalize)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  Iterable<String> _splitLines(String value) {
    return value.split(RegExp(r'\r\n|\r|\n'));
  }

  bool _isFirstPost(ThreadPost post) => post.isFirst || post.number == 1;

  bool _isAnchorOnlyLine(String line, Set<String> anchorTexts) {
    if (anchorTexts.contains(line)) {
      return true;
    }
    var remainder = line;
    final orderedAnchors = anchorTexts.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final anchorText in orderedAnchors) {
      remainder = remainder.replaceAll(anchorText, '');
    }
    return remainder.replaceAll(RegExp(r'[\s|/·,，、]+'), '').isEmpty;
  }

  bool _isCatalogGroupHeading({
    required List<String> lines,
    required int index,
    required Set<String> anchorTexts,
  }) {
    for (var next = index + 1; next < lines.length; next++) {
      final nextLine = lines[next];
      if (_metadataMarker.hasMatch(nextLine)) {
        continue;
      }
      return _isAnchorOnlyLine(nextLine, anchorTexts);
    }
    return false;
  }

  bool _isCatalogMarker(String line) {
    final marker = _metadataMarker.firstMatch(line)?.group(1);
    return marker == '目录' || marker == '目錄';
  }

  bool _isIntroMarker(String line) {
    final marker = _metadataMarker.firstMatch(line)?.group(1);
    return marker == '简介' || marker == '簡介';
  }

  String _normalize(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
