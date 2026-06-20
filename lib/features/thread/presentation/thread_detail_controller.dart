import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/thread/data/thread_favorite_providers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/thread_poll_vote_repository.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

class ThreadDetailArgs {
  const ThreadDetailArgs({required this.tid, this.subject = ''});

  final String tid;
  final String subject;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThreadDetailArgs &&
        other.tid == tid &&
        other.subject == subject;
  }

  @override
  int get hashCode => Object.hash(tid, subject);
}

final threadDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadDetailController, ThreadDetailPageState, ThreadDetailArgs>(
      (args) => ThreadDetailController(args),
    );

/// viewthread 分页控制器，支持首屏加载和向后翻页。
class ThreadDetailController extends AsyncNotifier<ThreadDetailPageState> {
  ThreadDetailController(this._args);

  final ThreadDetailArgs _args;

  @override
  FutureOr<ThreadDetailPageState> build() async {
    return _loadPage(
      page: 1,
      previous: const <ThreadPost>[],
      queryParameters: const <String, String>{},
    );
  }

  Future<void> refresh() async {
    final current = state.value;
    final currentPage = current?.currentPage;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadPage(
        page: currentPage == null || currentPage <= 0 ? 1 : currentPage,
        previous: const <ThreadPost>[],
        queryParameters: current?.queryParameters ?? const <String, String>{},
      ),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    final result = await _readRepository().getThreadDetail(
      tid: _args.tid,
      page: current.currentPage + 1,
      queryParameters: current.queryParameters,
    );

    state = result.when(
      success: (data) {
        final merged = <ThreadPost>[...current.posts, ...data.posts];
        return AsyncData(
          current.copyWith(
            subject: data.subject.isNotEmpty ? data.subject : current.subject,
            typeName: data.typeName,
            forumName: data.forumName,
            forumUrl: data.forumUrl,
            views: data.views,
            replies: data.replies,
            currentPage: data.currentPage,
            lastPage: data.lastPage,
            previousPageUrl: data.previousPageUrl,
            nextPageUrl: data.nextPageUrl,
            reverseOrderUrl: data.reverseOrderUrl,
            onlyAuthorUrl: data.onlyAuthorUrl,
            favoriteUrl: data.favoriteUrl,
            shareUrl: data.shareUrl,
            homeUrl: data.homeUrl,
            desktopUrl: data.desktopUrl,
            hasMore: data.hasMore,
            isLoadingMore: false,
            posts: merged,
            clearError: true,
          ),
        );
      },
      failure: (error) {
        return AsyncData(
          current.copyWith(isLoadingMore: false, errorMessage: error.message),
        );
      },
    );
  }

  Future<void> loadPage(int page) {
    return _replaceWithPage(page: page);
  }

  Future<void> loadPreviousPage() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final previousPage = _pageFromUrl(current.previousPageUrl);
    final fallbackPage = current.currentPage > 1 ? current.currentPage - 1 : 1;
    final targetPage = previousPage ?? fallbackPage;
    if (targetPage >= current.currentPage || targetPage < 1) {
      return;
    }
    await _replaceWithPage(page: targetPage);
  }

  Future<void> loadNextPage() async {
    final current = state.value;
    if (current == null || !current.hasMore) {
      return;
    }
    final nextPage = _pageFromUrl(current.nextPageUrl);
    await _replaceWithPage(page: nextPage ?? current.currentPage + 1);
  }

  Future<void> openOnlyAuthor() async {
    final current = state.value;
    final query = _queryFromUrl(current?.onlyAuthorUrl);
    if (current == null || query.isEmpty) {
      return;
    }
    await _replaceWithPage(
      page: _pageFromQuery(query) ?? 1,
      queryParameters: _threadDetailQuery(query),
    );
  }

  Future<void> openReverseOrder() async {
    final current = state.value;
    final query = _queryFromUrl(current?.reverseOrderUrl);
    if (current == null || query.isEmpty) {
      return;
    }
    await _replaceWithPage(
      page: _pageFromQuery(query) ?? current.currentPage,
      queryParameters: _threadDetailQuery(query),
    );
  }

  Future<void> resetThreadView() async {
    await _replaceWithPage(page: 1, queryParameters: const <String, String>{});
  }

  Future<void> addToShelf() async {
    final current = state.value;
    if (current == null ||
        current.isComicActionLoading ||
        current.contentKind != ThreadContentKind.comic) {
      return;
    }
    final snapshot = current;

    state = AsyncData(
      snapshot.copyWith(isComicActionLoading: true, clearError: true),
    );
    final comicId = _buildComicId(tid: snapshot.tid);

    try {
      await _readComicRepository().addToShelf(
        comicId: comicId,
        tid: snapshot.tid,
        fid: snapshot.fid,
        sourceTypeId: snapshot.typeid,
        sourceTagName: snapshot.sourceTagName,
        title: snapshot.subject,
        parsedPost: snapshot.parsedComicPost,
      );

      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(isComicActionLoading: false, isInShelf: true),
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(
          isComicActionLoading: false,
          errorMessage: '加入书架失败：$error',
        ),
      );
    }
  }

  Future<void> addNovelToShelf() async {
    final current = state.value;
    if (current == null ||
        current.isNovelActionLoading ||
        current.contentKind != ThreadContentKind.novel) {
      return;
    }
    final snapshot = current;

    state = AsyncData(
      snapshot.copyWith(isNovelActionLoading: true, clearError: true),
    );

    try {
      final fid = current.fid.trim();
      final tid = current.tid.trim();
      final repository = ref.read(novelRepositoryProvider);
      final novelId = 'novel:$fid:$tid';

      await repository.upsertNovelBySeed(
        seed: NovelRefreshSeed(
          fid: fid,
          tid: tid,
          typeid: current.typeid,
          tagName: current.sourceTagName,
        ),
      );
      await repository.refreshEpisodes(novelId: novelId);

      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(isNovelActionLoading: false, isNovelInShelf: true),
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        snapshot.copyWith(
          isNovelActionLoading: false,
          errorMessage: '加入小说书架失败：$error',
        ),
      );
    }
  }

  Future<void> favoriteThread() async {
    final current = state.value;
    if (current == null ||
        current.isThreadFavoriteActionLoading ||
        current.isThreadFavorited) {
      return;
    }
    final snapshot = current;

    state = AsyncData(
      snapshot.copyWith(
        isThreadFavoriteActionLoading: true,
        clearThreadFavoriteHint: true,
        clearError: true,
      ),
    );

    final result = await ref
        .read(threadFavoriteActionServiceProvider)
        .favoriteThread(tid: snapshot.tid);
    if (!ref.mounted) {
      return;
    }
    final afterAction = state.value ?? snapshot;
    state = result.when(
      success: (data) => AsyncData(
        afterAction.copyWith(
          isThreadFavoriteActionLoading: false,
          isThreadFavorited: true,
          threadFavoriteHint: data.message,
        ),
      ),
      failure: (error) => AsyncData(
        afterAction.copyWith(
          isThreadFavoriteActionLoading: false,
          threadFavoriteHint: error.message,
        ),
      ),
    );
  }

  void togglePollOption(ThreadPoll poll, ThreadPollOption option) {
    final current = state.value;
    if (current == null || current.isPollVoteSubmitting) {
      return;
    }
    final optionId = option.id.trim();
    if (optionId.isEmpty) {
      return;
    }
    final selected = Set<String>.from(current.selectedPollOptionIds);
    if (poll.isMultipleChoice) {
      final alreadySelected = selected.contains(optionId);
      if (alreadySelected) {
        selected.remove(optionId);
      } else {
        final maxChoices = poll.maxChoices;
        if (maxChoices != null &&
            maxChoices > 0 &&
            selected.length >= maxChoices) {
          state = AsyncData(
            current.copyWith(
              pollVoteHint: '最多可选 $maxChoices 项',
              clearError: true,
            ),
          );
          return;
        }
        selected.add(optionId);
      }
    } else {
      selected
        ..clear()
        ..add(optionId);
    }
    state = AsyncData(
      current.copyWith(
        selectedPollOptionIds: Set<String>.unmodifiable(selected),
        clearPollVoteHint: true,
        clearError: true,
      ),
    );
  }

  Future<void> submitPollVote(ThreadPoll poll) async {
    final current = state.value;
    if (current == null || current.isPollVoteSubmitting) {
      return;
    }
    final selected = current.selectedPollOptionIds.toList(growable: false);
    if (selected.isEmpty) {
      state = AsyncData(current.copyWith(pollVoteHint: '请选择投票选项'));
      return;
    }

    state = AsyncData(
      current.copyWith(
        isPollVoteSubmitting: true,
        clearPollVoteHint: true,
        clearError: true,
      ),
    );
    final result = await ref
        .read(threadPollVoteRepositoryProvider)
        .vote(
          ThreadPollVoteRequest(
            tid: current.tid,
            actionUrl: poll.actionUrl ?? '',
            formHash: poll.formHash ?? '',
            optionIds: selected,
          ),
        );
    if (!ref.mounted) {
      return;
    }
    final afterSubmit = state.value ?? current;
    if (result case ApiFailure<ThreadPollVoteResult>(:final error)) {
      state = AsyncData(
        afterSubmit.copyWith(
          isPollVoteSubmitting: false,
          pollVoteHint: error.message,
        ),
      );
      return;
    }

    final message = (result as ApiSuccess<ThreadPollVoteResult>).data.message
        .trim();
    final reloaded = await _loadPage(
      page: afterSubmit.currentPage <= 0 ? 1 : afterSubmit.currentPage,
      previous: const <ThreadPost>[],
      queryParameters: afterSubmit.queryParameters,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      reloaded.copyWith(
        isThreadFavorited: afterSubmit.isThreadFavorited,
        threadFavoriteHint: afterSubmit.threadFavoriteHint,
        pollVoteHint: message.isEmpty ? '投票成功' : message,
        selectedPollOptionIds: const <String>{},
        isPollVoteSubmitting: false,
      ),
    );
  }

  Future<ApiResult<ThreadPostRateForm>> loadRateForm(ThreadPost post) async {
    final rateUrl = post.rateUrl?.trim();
    if (rateUrl == null || rateUrl.isEmpty) {
      return const ApiFailure<ThreadPostRateForm>(
        ApiError(type: ApiErrorType.business, message: '评分表单地址缺失'),
      );
    }
    return ref.read(threadPostRateRepositoryProvider).loadForm(rateUrl);
  }

  Future<ApiResult<ThreadPostRateResult>> submitPostRate(
    ThreadPostRateDraft draft,
  ) async {
    final result = await ref
        .read(threadPostRateRepositoryProvider)
        .submit(draft);
    if (result case ApiFailure<ThreadPostRateResult>()) {
      return result;
    }
    final current = state.value;
    if (current != null) {
      final reloaded = await _loadPage(
        page: current.currentPage <= 0 ? 1 : current.currentPage,
        previous: const <ThreadPost>[],
        queryParameters: current.queryParameters,
      );
      if (ref.mounted) {
        state = AsyncData(
          reloaded.copyWith(
            isThreadFavorited: current.isThreadFavorited,
            threadFavoriteHint: current.threadFavoriteHint,
          ),
        );
      }
    }
    return result;
  }

  void updateReplyText(String value) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(replyText: value, clearReplyHint: true));
  }

  Future<void> submitReply() async {
    final current = state.value;
    if (current == null || current.isReplySubmitting) {
      return;
    }
    final message = current.replyText.trim();
    if (message.isEmpty) {
      state = AsyncData(current.copyWith(replyHint: '请输入回复内容'));
      return;
    }

    state = AsyncData(
      current.copyWith(isReplySubmitting: true, clearReplyHint: true),
    );

    final result = await ref
        .read(replyRepositoryProvider)
        .sendReply(
          draft: ReplyDraft(
            fid: current.fid,
            tid: current.tid,
            message: message,
          ),
        );

    final afterSubmit = state.value ?? current;
    state = result.when(
      success: (data) => AsyncData(
        afterSubmit.copyWith(
          isReplySubmitting: false,
          replyText: '',
          replyHint: data.message.isEmpty ? '回复成功' : data.message,
        ),
      ),
      failure: (error) => AsyncData(
        afterSubmit.copyWith(
          isReplySubmitting: false,
          replyHint: error.message,
        ),
      ),
    );

    if (result.isSuccess) {
      final latest = state.value;
      if (latest == null) {
        return;
      }
      final reloaded = await _loadPage(
        page: latest.currentPage <= 0 ? 1 : latest.currentPage,
        previous: const <ThreadPost>[],
        queryParameters: latest.queryParameters,
      );
      state = AsyncData(
        reloaded.copyWith(
          replyHint: latest.replyHint,
          replyText: latest.replyText,
          isThreadFavorited: latest.isThreadFavorited,
          threadFavoriteHint: latest.threadFavoriteHint,
        ),
      );
    }
  }

  Future<ThreadDetailPageState> _loadPage({
    required int page,
    required List<ThreadPost> previous,
    required Map<String, String> queryParameters,
  }) async {
    final result = await _readRepository().getThreadDetail(
      tid: _args.tid,
      page: page,
      queryParameters: queryParameters,
    );

    if (result case ApiSuccess<ThreadDetailData>(:final data)) {
      final merged = page == 1
          ? data.posts
          : <ThreadPost>[...previous, ...data.posts];
      final aggregation = ref
          .read(comicPostAggregationServiceProvider)
          .build(merged);
      final subject = data.subject.isNotEmpty ? data.subject : _args.subject;
      final sourceTagName = await _findSourceTagName(
        fid: data.fid,
        typeid: data.typeid,
      );
      final contentKind = ref
          .read(threadContentClassifierProvider)
          .classify(fid: data.fid, typeid: data.typeid, tagName: sourceTagName);
      final comicMeta = _parseComicWhenTagged(
        isComic: contentKind == ThreadContentKind.comic,
        subject: data.subject.isNotEmpty ? data.subject : _args.subject,
        parseMessage: aggregation.parseMessage,
        attachmentImageUrls: aggregation.attachmentImageUrls,
      );
      // 内容类型由 fid + typeid + 来源标签统一判定，避免漫画/小说入口各自维护规则。
      final comicCandidate = contentKind == ThreadContentKind.comic;
      final comicId = _buildComicId(tid: _args.tid);
      final isInShelf = comicCandidate
          ? await _readComicRepository().isInShelf(comicId: comicId)
          : false;
      final novelCandidate = contentKind == ThreadContentKind.novel;
      var isNovelInShelf = false;
      if (novelCandidate) {
        final novelId = 'novel:${data.fid}:${_args.tid}';
        isNovelInShelf =
            await ref
                .read(novelRepositoryProvider)
                .getDetail(novelId: novelId) !=
            null;
      }

      return ThreadDetailPageState(
        tid: _args.tid,
        fid: data.fid,
        typeid: data.typeid,
        typeName: data.typeName,
        forumName: data.forumName,
        forumUrl: data.forumUrl,
        sourceTagName: sourceTagName,
        contentKind: contentKind,
        subject: subject,
        views: data.views,
        replies: data.replies,
        currentPage: data.currentPage,
        lastPage: data.lastPage,
        previousPageUrl: data.previousPageUrl,
        nextPageUrl: data.nextPageUrl,
        reverseOrderUrl: data.reverseOrderUrl,
        onlyAuthorUrl: data.onlyAuthorUrl,
        favoriteUrl: data.favoriteUrl,
        shareUrl: data.shareUrl,
        homeUrl: data.homeUrl,
        desktopUrl: data.desktopUrl,
        hasMore: data.hasMore,
        queryParameters: Map<String, String>.unmodifiable(queryParameters),
        isLoadingInitial: false,
        isLoadingMore: false,
        posts: merged,
        comicCandidateInfo: comicMeta.$1,
        parsedComicPost: comicMeta.$2,
        isInShelf: isInShelf,
        isComicActionLoading: false,
        isNovelCandidate: novelCandidate,
        isNovelInShelf: isNovelInShelf,
        isNovelActionLoading: false,
        isThreadFavorited: false,
        isThreadFavoriteActionLoading: false,
        threadFavoriteHint: null,
        selectedPollOptionIds: const <String>{},
        isPollVoteSubmitting: false,
        pollVoteHint: null,
        replyText: '',
        isReplySubmitting: false,
        replyHint: null,
      );
    }

    final error = (result as ApiFailure<ThreadDetailData>).error;
    return ThreadDetailPageState(
      tid: _args.tid,
      fid: '',
      typeid: '',
      typeName: null,
      forumName: null,
      forumUrl: null,
      sourceTagName: null,
      contentKind: ThreadContentKind.forum,
      subject: _args.subject,
      views: 0,
      replies: 0,
      currentPage: page == 1 ? 0 : page,
      lastPage: null,
      previousPageUrl: null,
      nextPageUrl: null,
      reverseOrderUrl: null,
      onlyAuthorUrl: null,
      favoriteUrl: null,
      shareUrl: null,
      homeUrl: null,
      desktopUrl: null,
      hasMore: false,
      queryParameters: Map<String, String>.unmodifiable(queryParameters),
      isLoadingInitial: false,
      isLoadingMore: false,
      posts: previous,
      comicCandidateInfo: ComicCandidateInfo.notCandidate,
      parsedComicPost: ParsedComicPost.empty,
      isInShelf: false,
      isComicActionLoading: false,
      isNovelCandidate: false,
      isNovelInShelf: false,
      isNovelActionLoading: false,
      isThreadFavorited: false,
      isThreadFavoriteActionLoading: false,
      threadFavoriteHint: null,
      selectedPollOptionIds: const <String>{},
      isPollVoteSubmitting: false,
      pollVoteHint: null,
      replyText: '',
      isReplySubmitting: false,
      replyHint: null,
      errorMessage: error.message,
    );
  }

  Future<void> _replaceWithPage({
    required int page,
    Map<String, String>? queryParameters,
  }) async {
    final current = state.value;
    if (current == null || current.isLoadingMore) {
      return;
    }
    final nextQuery = queryParameters ?? current.queryParameters;
    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    final next = await _loadPage(
      page: page,
      previous: const <ThreadPost>[],
      queryParameters: nextQuery,
    );
    final afterLoading = state.value ?? current;
    state = AsyncData(
      next.copyWith(
        isThreadFavorited: afterLoading.isThreadFavorited,
        threadFavoriteHint: afterLoading.threadFavoriteHint,
        selectedPollOptionIds: afterLoading.selectedPollOptionIds,
        isPollVoteSubmitting: false,
      ),
    );
  }

  int? _pageFromUrl(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    final queryPage = int.tryParse(uri?.queryParameters['page'] ?? '');
    if (queryPage != null) {
      return queryPage;
    }
    final path = uri?.path ?? '';
    return int.tryParse(
      RegExp(r'thread-\d+-(\d+)-').firstMatch(path)?.group(1) ?? '',
    );
  }

  Map<String, String> _queryFromUrl(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return const <String, String>{};
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      return const <String, String>{};
    }
    final query = Map<String, String>.from(parsed.queryParameters);
    final page = _pageFromUrl(value);
    if (page != null) {
      query['page'] = page.toString();
    }
    return query;
  }

  int? _pageFromQuery(Map<String, String> query) {
    return int.tryParse(query['page'] ?? '');
  }

  Map<String, String> _threadDetailQuery(Map<String, String> query) {
    const allowedKeys = <String>{
      'authorid',
      'ordertype',
      'extra',
      'from',
      'page',
    };
    return Map<String, String>.unmodifiable({
      for (final entry in query.entries)
        if (allowedKeys.contains(entry.key) && entry.value.trim().isNotEmpty)
          entry.key: entry.value,
    });
  }

  ThreadRepository _readRepository() {
    return ref.read(threadRepositoryProvider);
  }

  ComicRepository _readComicRepository() {
    return ref.read(comicRepositoryProvider);
  }

  (ComicCandidateInfo, ParsedComicPost) _parseComicWhenTagged({
    required bool isComic,
    required String subject,
    required String parseMessage,
    required List<String> attachmentImageUrls,
  }) {
    if (!isComic || (parseMessage.isEmpty && attachmentImageUrls.isEmpty)) {
      return (ComicCandidateInfo.notCandidate, ParsedComicPost.empty);
    }

    final parser = ref.read(comicParserServiceProvider);
    final subjectParser = ref.read(comicSubjectParserProvider);
    final parsed = parser
        .parseInput(
          ComicPostParseInput(
            messageHtml: parseMessage,
            attachmentImageUrls: attachmentImageUrls,
          ),
        )
        .copyWith(subjectMetadata: subjectParser.parse(subject));
    return (
      const ComicCandidateInfo(
        isCandidate: true,
        score: 100,
        reasons: <String>['tag-rule'],
      ),
      parsed,
    );
  }

  String _buildComicId({required String tid}) {
    return 'yamibo:$tid';
  }

  Future<String?> _findSourceTagName({
    required String fid,
    required String typeid,
  }) async {
    if (fid.trim().isEmpty || typeid.trim().isEmpty) {
      return null;
    }
    try {
      final lookup = await ref.read(forumTagLookupProvider.future);
      return lookup.findName(fid: fid, typeid: typeid);
    } catch (_) {
      // 标签 asset 失败不应阻断帖子正文；分类服务仍会用公告 typeid 兜底。
      return null;
    }
  }
}
