import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/thread/data/providers/thread_favorite_providers.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_poll_vote_repository.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/domain/models/thread_ui_feedback.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

class ThreadDetailArgs {
  const ThreadDetailArgs({
    required this.tid,
    this.subject = '',
    this.initialPage,
    this.targetPid,
  });

  final String tid;
  final String subject;
  final int? initialPage;
  final String? targetPid;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThreadDetailArgs &&
        other.tid == tid &&
        other.subject == subject &&
        other.initialPage == initialPage &&
        other.targetPid == targetPid;
  }

  @override
  int get hashCode => Object.hash(tid, subject, initialPage, targetPid);
}

final threadDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadDetailController, ThreadDetailPageState, ThreadDetailArgs>(
      (args) => ThreadDetailController(args),
    );

/// viewthread 分页控制器，支持首屏加载和向后翻页。
class ThreadDetailController extends AsyncNotifier<ThreadDetailPageState> {
  ThreadDetailController(this._args);

  final ThreadDetailArgs _args;
  final Map<String, Object> _ratingsLoadTokens = <String, Object>{};
  var _ratingsContentGeneration = 0;

  @override
  FutureOr<ThreadDetailPageState> build() async {
    final initialPage = _args.initialPage == null || _args.initialPage! <= 0
        ? 1
        : _args.initialPage!;
    return _loadPage(
      page: initialPage,
      previous: const <ThreadPost>[],
      queryParameters: const <String, String>{},
    );
  }

  /// 重新加载当前页，保留当前的筛选/排序参数。
  ///
  /// [forceNetwork] 会先清掉本帖的文档与解析快照缓存。快照有 5 分钟新鲜期，不清
  /// 缓存的话下拉刷新会直接命中快照、看不到新回复，手势等于空转——这是用户主动
  /// 要求刷新的场景，必须真的走一次网络。
  Future<void> refresh({bool forceNetwork = false}) async {
    if (forceNetwork) {
      await _invalidateCurrentThreadCache(state.value?.tid ?? _args.tid);
    }
    final current = state.value;
    final currentPage = current?.currentPage;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadPage(
        page: currentPage == null || currentPage <= 0 ? 1 : currentPage,
        previous: const <ThreadPost>[],
        queryParameters: current?.queryParameters ?? const <String, String>{},
        failureCode: ThreadUiErrorCode.refreshFailed,
      ),
    );
  }

  Future<void> refreshAfterMutation() => refresh(forceNetwork: true);

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    final result = await _readRepository().getThreadDetail(
      tid: _args.tid,
      page: current.currentPage + 1,
      query: ThreadDetailQuery.fromLegacyParameters(current.queryParameters),
    );

    state = result.when(
      success: (data, capabilities, metadata) {
        final effectiveCapabilities = current.capabilities == null
            ? capabilities
            : current.capabilities!.intersect(capabilities);
        final effectiveMetadata = current.readMetadata == null
            ? metadata
            : current.readMetadata!.merge(metadata);
        final merged = _preparePostsForView(<ThreadPost>[
          ...current.posts,
          ...data.posts,
        ], current.queryParameters);
        return AsyncData(
          current.copyWith(
            subject: data.subject.isNotEmpty ? data.subject : current.subject,
            typeName: data.typeName,
            forumName: data.forumName,
            forumUrl: data.forumUrl,
            views: data.views,
            replies: data.replies,
            currentPage: data.currentPage,
            lastPage:
                effectiveCapabilities.supports(
                  ThreadDetailCapability.exactPagination,
                )
                ? data.lastPage
                : null,
            previousPageUrl: data.previousPageUrl,
            nextPageUrl: data.nextPageUrl,
            reverseOrderUrl:
                effectiveCapabilities.supports(
                  ThreadDetailCapability.alternateViews,
                )
                ? data.reverseOrderUrl
                : null,
            onlyAuthorUrl:
                effectiveCapabilities.supports(
                  ThreadDetailCapability.alternateViews,
                )
                ? data.onlyAuthorUrl
                : null,
            favoriteUrl:
                effectiveCapabilities.supports(
                  ThreadDetailCapability.favoriteEntry,
                )
                ? data.favoriteUrl
                : null,
            shareUrl: data.shareUrl,
            homeUrl: data.homeUrl,
            desktopUrl: data.desktopUrl,
            hasMore: data.hasMore,
            isLoadingMore: false,
            posts: merged,
            capabilities: effectiveCapabilities,
            readMetadata: effectiveMetadata,
            clearLastPage: !effectiveCapabilities.supports(
              ThreadDetailCapability.exactPagination,
            ),
            clearReverseOrderUrl: !effectiveCapabilities.supports(
              ThreadDetailCapability.alternateViews,
            ),
            clearOnlyAuthorUrl: !effectiveCapabilities.supports(
              ThreadDetailCapability.alternateViews,
            ),
            clearFavoriteUrl: !effectiveCapabilities.supports(
              ThreadDetailCapability.favoriteEntry,
            ),
            clearError: true,
          ),
        );
      },
      failure: (failure) {
        return AsyncData(
          current.copyWith(
            isLoadingMore: false,
            errorMessage: failure.diagnosticMessage,
            loadFailure: ThreadActionFailure(
              code: failure.kind == DataReadFailureKind.unauthorized
                  ? ThreadUiErrorCode.loginRequired
                  : ThreadUiErrorCode.pageLoadFailed,
              detail: failure.diagnosticMessage,
              message: failure.diagnosticMessage,
            ),
          ),
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
    if (current == null ||
        !current.supports(ThreadDetailCapability.alternateViews)) {
      return;
    }
    final authorId =
        _queryFromUrl(current.onlyAuthorUrl)['authorid'] ??
        _firstAvailableAuthorId(current.posts);
    if (authorId == null || authorId.trim().isEmpty) {
      return;
    }
    await _replaceWithPage(
      page: 1,
      queryParameters: _withQueryUpdates(
        current.queryParameters,
        set: <String, String>{'authorid': authorId.trim()},
        remove: const <String>{'page'},
      ),
    );
  }

  Future<void> openAllPosts() async {
    final current = state.value;
    if (current == null ||
        !current.supports(ThreadDetailCapability.alternateViews) ||
        !current.isOnlyAuthorView) {
      return;
    }
    await _replaceWithPage(
      page: 1,
      queryParameters: _withQueryUpdates(
        current.queryParameters,
        remove: const <String>{'authorid', 'page'},
      ),
    );
  }

  Future<void> openReverseOrder() async {
    final current = state.value;
    if (current == null ||
        !current.supports(ThreadDetailCapability.alternateViews)) {
      return;
    }
    await _replaceWithPage(
      page: 1,
      queryParameters: _withQueryUpdates(
        current.queryParameters,
        set: const <String, String>{'ordertype': '1'},
        remove: const <String>{'page'},
      ),
    );
  }

  Future<void> openNormalOrder() async {
    final current = state.value;
    if (current == null ||
        !current.supports(ThreadDetailCapability.alternateViews) ||
        !current.isReverseOrderView) {
      return;
    }
    await _replaceWithPage(
      page: 1,
      queryParameters: _withQueryUpdates(
        current.queryParameters,
        set: const <String, String>{'ordertype': '2'},
        remove: const <String>{'page'},
      ),
    );
  }

  Future<void> resetThreadView() async {
    await _replaceWithPage(page: 1, queryParameters: const <String, String>{});
  }

  Future<void> favoriteThread() async {
    final current = state.value;
    if (current == null ||
        !current.supports(ThreadDetailCapability.favoriteEntry) ||
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
          threadFavoriteNotice: ThreadActionNotice(
            code: ThreadActionNoticeCode.success,
            action: ThreadActionKind.favorite,
            detail: data.message,
          ),
        ),
      ),
      failure: (error) => AsyncData(
        afterAction.copyWith(
          isThreadFavoriteActionLoading: false,
          threadFavoriteHint: error.message,
          threadFavoriteNotice: ThreadActionNotice(
            code: _noticeCodeFor(error),
            action: ThreadActionKind.favorite,
            detail: error.message,
            message: error.message,
          ),
        ),
      ),
    );
  }

  void togglePollOption(ThreadPoll poll, ThreadPollOption option) {
    final current = state.value;
    if (current == null || current.isPollVoteSubmitting || !poll.canVote) {
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
              pollVoteNotice: ThreadActionNotice(
                code: ThreadActionNoticeCode.validation,
                action: ThreadActionKind.vote,
                maxChoices: maxChoices,
              ),
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
    if (current == null ||
        !current.supports(ThreadDetailCapability.pollVoteAction) ||
        current.isPollVoteSubmitting ||
        !poll.canVote) {
      return;
    }
    final selected = current.selectedPollOptionIds.toList(growable: false);
    if (selected.isEmpty) {
      state = AsyncData(
        current.copyWith(
          pollVoteNotice: const ThreadActionNotice(
            code: ThreadActionNoticeCode.validation,
            action: ThreadActionKind.vote,
          ),
        ),
      );
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
          pollVoteNotice: ThreadActionNotice(
            code: _noticeCodeFor(error),
            action: ThreadActionKind.vote,
            detail: error.message,
            message: error.message,
          ),
        ),
      );
      return;
    }

    final message = (result as ApiSuccess<ThreadPollVoteResult>).data.message
        .trim();
    await _invalidateCurrentThreadCache(afterSubmit.tid);
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
        pollVoteHint: message.isEmpty ? null : message,
        pollVoteNotice: ThreadActionNotice(
          code: ThreadActionNoticeCode.success,
          action: ThreadActionKind.vote,
          detail: message,
        ),
        selectedPollOptionIds: const <String>{},
        isPollVoteSubmitting: false,
      ),
    );
  }

  Future<void> loadAllRatings(ThreadPost post) async {
    final current = state.value;
    final pid = post.pid.trim();
    final viewAllUrl = post.ratingSummary?.viewAllUrl?.trim();
    if (current == null ||
        !current.supports(ThreadDetailCapability.ratingSummary) ||
        pid.isEmpty ||
        viewAllUrl == null ||
        viewAllUrl.isEmpty) {
      return;
    }
    final existing = current.ratingsByPostId[pid];
    if (existing?.status == ThreadPostRatingsLoadStatus.loading ||
        existing?.status == ThreadPostRatingsLoadStatus.loaded) {
      return;
    }

    final token = Object();
    final contentGeneration = _ratingsContentGeneration;
    _ratingsLoadTokens[pid] = token;
    state = AsyncData(
      current.copyWith(
        ratingsByPostId: Map<String, ThreadPostRatingsViewState>.unmodifiable(
          <String, ThreadPostRatingsViewState>{
            ...current.ratingsByPostId,
            pid: const ThreadPostRatingsViewState.loading(),
          },
        ),
      ),
    );

    final result = await ref
        .read(threadPostRatingsRepositoryProvider)
        .loadAll(viewAllUrl);
    if (!ref.mounted ||
        contentGeneration != _ratingsContentGeneration ||
        !identical(_ratingsLoadTokens[pid], token)) {
      return;
    }

    final latest = state.value;
    final activePost = latest == null
        ? null
        : _findPostByPid(latest.posts, pid);
    final activeUrl = activePost?.ratingSummary?.viewAllUrl?.trim();
    if (latest == null ||
        latest.tid != current.tid ||
        activeUrl != viewAllUrl ||
        latest.ratingsByPostId[pid]?.status !=
            ThreadPostRatingsLoadStatus.loading) {
      _ratingsLoadTokens.remove(pid);
      return;
    }

    final nextViewState = switch (result) {
      ApiSuccess<ThreadPostRatingDetails>(:final data) =>
        ThreadPostRatingsViewState.loaded(data),
      ApiFailure<ThreadPostRatingDetails>(:final error) =>
        ThreadPostRatingsViewState.failureWith(
          ThreadActionFailure(
            code: _errorCodeFor(error, ThreadUiErrorCode.unknown),
            action: ThreadActionKind.ratings,
            detail: error.message,
            message: error.message,
          ),
        ),
    };
    state = AsyncData(
      latest.copyWith(
        ratingsByPostId: Map<String, ThreadPostRatingsViewState>.unmodifiable(
          <String, ThreadPostRatingsViewState>{
            ...latest.ratingsByPostId,
            pid: nextViewState,
          },
        ),
      ),
    );
    _ratingsLoadTokens.remove(pid);
  }

  Future<ApiResult<ThreadPostRateForm>> loadRateForm(ThreadPost post) async {
    final current = state.value;
    final rateUrl = post.rateUrl?.trim();
    if (rateUrl == null || rateUrl.isEmpty) {
      return const ApiFailure<ThreadPostRateForm>(
        ApiError(type: ApiErrorType.business, message: '评分表单地址缺失'),
      );
    }
    return ref
        .read(threadPostRateRepositoryProvider)
        .loadFormFromSeed(
          ThreadPostRateFormSeed(
            rateUrl: rateUrl,
            tid: current?.tid ?? _args.tid,
            pid: post.pid,
            referer: _rateReferer(current, post),
          ),
        );
  }

  ThreadPost? _findPostByPid(List<ThreadPost> posts, String pid) {
    for (final post in posts) {
      if (post.pid.trim() == pid) {
        return post;
      }
    }
    return null;
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
      await _invalidateCurrentThreadCache(current.tid);
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

  Future<ApiResult<ThreadPostCommentForm>> loadCommentForm(
    ThreadPost post,
  ) async {
    final current = state.value;
    final pid = post.pid.trim();
    if (pid.isEmpty) {
      return const ApiFailure<ThreadPostCommentForm>(
        ApiError(type: ApiErrorType.business, message: '点评楼层缺失'),
      );
    }
    final tid = current?.tid.trim().isNotEmpty == true
        ? current!.tid.trim()
        : _args.tid;
    final page = current?.currentPage ?? 1;
    final commentUrl = post.commentUrl?.trim();
    if (commentUrl == null || commentUrl.isEmpty) {
      return const ApiFailure<ThreadPostCommentForm>(
        ApiError(type: ApiErrorType.business, message: '点评入口缺失'),
      );
    }
    return ref
        .read(threadPostCommentRepositoryProvider)
        .loadFormFromSeed(
          ThreadPostCommentFormSeed(
            commentUrl: commentUrl,
            tid: tid,
            pid: pid,
            page: page <= 0 ? 1 : page,
          ),
        );
  }

  Future<ApiResult<ThreadPostCommentResult>> submitPostComment(
    ThreadPostCommentDraft draft,
  ) async {
    final result = await ref
        .read(threadPostCommentRepositoryProvider)
        .submit(draft);
    if (result case ApiFailure<ThreadPostCommentResult>()) {
      return result;
    }
    final current = state.value;
    if (current != null) {
      await _invalidateCurrentThreadCache(current.tid);
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
      state = AsyncData(
        current.copyWith(
          replyNotice: const ThreadActionNotice(
            code: ThreadActionNoticeCode.validation,
            action: ThreadActionKind.reply,
          ),
        ),
      );
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
          replyHint: data.message.isEmpty ? null : data.message,
          replyNotice: ThreadActionNotice(
            code: ThreadActionNoticeCode.success,
            action: ThreadActionKind.reply,
            detail: data.message,
          ),
        ),
      ),
      failure: (error) => AsyncData(
        afterSubmit.copyWith(
          isReplySubmitting: false,
          replyHint: error.message,
          replyNotice: ThreadActionNotice(
            code: _noticeCodeFor(error),
            action: ThreadActionKind.reply,
            detail: error.message,
            message: error.message,
          ),
        ),
      ),
    );

    if (result.isSuccess) {
      final latest = state.value;
      if (latest == null) {
        return;
      }
      await _invalidateCurrentThreadCache(latest.tid);
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
          threadFavoriteNotice: latest.threadFavoriteNotice,
          replyNotice: latest.replyNotice,
        ),
      );
    }
  }

  Future<ThreadDetailPageState> _loadPage({
    required int page,
    required List<ThreadPost> previous,
    required Map<String, String> queryParameters,
    ThreadUiErrorCode? failureCode,
  }) async {
    _ratingsContentGeneration += 1;
    _ratingsLoadTokens.clear();
    _logNative(
      'controller_load',
      'tid=${_args.tid} page=$page previous=${previous.length} '
          'query=${_formatQuery(queryParameters)}',
    );
    final result = await _readRepository().getThreadDetail(
      tid: _args.tid,
      page: page,
      query: ThreadDetailQuery.fromLegacyParameters(queryParameters),
    );

    if (result
        case DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>(
          :final data,
          :final capabilities,
          :final metadata,
        )) {
      _logNative(
        'controller_repository_success',
        'tid=${_args.tid} requestedPage=$page parsedPage=${data.currentPage} '
            'fid=${data.fid} typeid=${data.typeid} posts=${data.posts.length} '
            'previous=${previous.length} subjectLength=${data.subject.length} '
            'firstPid=${data.posts.isEmpty ? '-' : data.posts.first.pid} '
            'firstMessageLength=${data.posts.isEmpty ? 0 : data.posts.first.message.length}',
      );
      var stage = 'merge';
      try {
        _logNative(
          'controller_merge_start',
          'tid=${_args.tid} requestedPage=$page incoming=${data.posts.length} '
              'previous=${previous.length} query=${_formatQuery(queryParameters)}',
        );
        final merged = _preparePostsForView(
          page == 1 ? data.posts : <ThreadPost>[...previous, ...data.posts],
          queryParameters,
        );
        _logNative(
          'controller_merge_done',
          'tid=${_args.tid} posts=${merged.length} '
              'firstPid=${merged.isEmpty ? '-' : merged.first.pid} '
              'firstNo=${merged.isEmpty ? '-' : merged.first.number}',
        );

        final subject = data.subject.isNotEmpty ? data.subject : _args.subject;
        stage = 'tag_lookup';
        final tagLookupStopwatch = Stopwatch()..start();
        _logNative(
          'controller_tag_lookup_start',
          'tid=${_args.tid} fid=${data.fid} typeid=${data.typeid}',
        );
        final sourceTagName = await _findSourceTagName(
          fid: data.fid,
          typeid: data.typeid,
        );
        tagLookupStopwatch.stop();
        _logNative(
          'controller_tag_lookup_done',
          'tid=${_args.tid} elapsedMs=${tagLookupStopwatch.elapsedMilliseconds} '
              'tag=${sourceTagName ?? '-'}',
        );

        stage = 'classify';
        _logNative(
          'controller_classify_start',
          'tid=${_args.tid} fid=${data.fid} typeid=${data.typeid} '
              'tag=${sourceTagName ?? '-'}',
        );
        final contentKind = ref
            .read(threadContentClassifierProvider)
            .classify(
              fid: data.fid,
              typeid: data.typeid,
              tagName: sourceTagName,
            );
        _logNative(
          'controller_classify_done',
          'tid=${_args.tid} kind=${contentKind.name}',
        );

        stage = 'state_build';
        _logNative(
          'controller_state_build_start',
          'tid=${_args.tid} posts=${merged.length} kind=${contentKind.name}',
        );
        final viewState = ThreadDetailPageState(
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
          lastPage:
              capabilities.supports(ThreadDetailCapability.exactPagination)
              ? data.lastPage
              : null,
          previousPageUrl: data.previousPageUrl,
          nextPageUrl: data.nextPageUrl,
          reverseOrderUrl:
              capabilities.supports(ThreadDetailCapability.alternateViews)
              ? data.reverseOrderUrl
              : null,
          onlyAuthorUrl:
              capabilities.supports(ThreadDetailCapability.alternateViews)
              ? data.onlyAuthorUrl
              : null,
          favoriteUrl:
              capabilities.supports(ThreadDetailCapability.favoriteEntry)
              ? data.favoriteUrl
              : null,
          shareUrl: data.shareUrl,
          homeUrl: data.homeUrl,
          desktopUrl: data.desktopUrl,
          hasMore: data.hasMore,
          queryParameters: Map<String, String>.unmodifiable(queryParameters),
          isLoadingInitial: false,
          isLoadingMore: false,
          posts: merged,
          isThreadFavorited: false,
          isThreadFavoriteActionLoading: false,
          threadFavoriteHint: null,
          selectedPollOptionIds: const <String>{},
          isPollVoteSubmitting: false,
          pollVoteHint: null,
          replyText: '',
          isReplySubmitting: false,
          replyHint: null,
          capabilities: capabilities,
          readMetadata: metadata,
        );
        _logNative(
          'controller_success',
          'tid=${_args.tid} requestedPage=$page parsedPage=${data.currentPage} '
              'posts=${merged.length} previous=${previous.length} fid=${data.fid} '
              'typeid=${data.typeid} tag=${sourceTagName ?? '-'} '
              'kind=${contentKind.name} subjectLength=${subject.length} '
              'firstPid=${merged.isEmpty ? '-' : merged.first.pid} '
              'firstMessageLength=${merged.isEmpty ? 0 : merged.first.message.length}',
        );
        return viewState;
      } catch (error, stackTrace) {
        _logNative(
          'controller_processing_failure',
          'tid=${_args.tid} page=$page stage=$stage '
              'error=${_oneLine(error.toString())} '
              'stack=${_stackHead(stackTrace)}',
        );
        return _failureState(
          page: page,
          previous: previous,
          queryParameters: queryParameters,
          message: '帖子详情处理失败（$stage）：${_oneLine(error.toString())}',
          failure: ThreadActionFailure(
            code:
                failureCode ??
                (page == 1
                    ? ThreadUiErrorCode.loadFailed
                    : ThreadUiErrorCode.pageLoadFailed),
            detail: error.toString(),
          ),
        );
      }
    }

    final failure =
        result
            as DataReadFailure<ThreadDetailData, ThreadDetailReadCapabilities>;
    _logNative(
      'controller_failure',
      'tid=${_args.tid} page=$page previous=${previous.length} '
          'type=${failure.kind.name} status=${failure.statusCode ?? '-'} '
          'message=${_oneLine(failure.diagnosticMessage)}',
    );
    return _failureState(
      page: page,
      previous: previous,
      queryParameters: queryParameters,
      message: failure.diagnosticMessage,
      failure: ThreadActionFailure(
        code: failure.kind == DataReadFailureKind.unauthorized
            ? ThreadUiErrorCode.loginRequired
            : (failureCode ??
                  (page == 1
                      ? ThreadUiErrorCode.loadFailed
                      : ThreadUiErrorCode.pageLoadFailed)),
        detail: failure.diagnosticMessage,
        message: failure.diagnosticMessage,
      ),
    );
  }

  ThreadDetailPageState _failureState({
    required int page,
    required List<ThreadPost> previous,
    required Map<String, String> queryParameters,
    required String message,
    required ThreadActionFailure failure,
  }) {
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
      isThreadFavorited: false,
      isThreadFavoriteActionLoading: false,
      threadFavoriteHint: null,
      selectedPollOptionIds: const <String>{},
      isPollVoteSubmitting: false,
      pollVoteHint: null,
      replyText: '',
      isReplySubmitting: false,
      replyHint: null,
      errorMessage: message,
      loadFailure: failure,
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
      failureCode: ThreadUiErrorCode.pageLoadFailed,
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

  Map<String, String> _withQueryUpdates(
    Map<String, String> base, {
    Map<String, String> set = const <String, String>{},
    Set<String> remove = const <String>{},
  }) {
    final next = Map<String, String>.from(_threadDetailQuery(base));
    for (final key in remove) {
      next.remove(key);
    }
    for (final entry in set.entries) {
      final value = entry.value.trim();
      if (value.isEmpty) {
        next.remove(entry.key);
      } else {
        next[entry.key] = value;
      }
    }
    return Map<String, String>.unmodifiable(next);
  }

  String? _firstAvailableAuthorId(List<ThreadPost> posts) {
    for (final post in posts) {
      final authorId = post.authorId.trim();
      if (authorId.isNotEmpty) {
        return authorId;
      }
    }
    return null;
  }

  List<ThreadPost> _preparePostsForView(
    List<ThreadPost> posts,
    Map<String, String> queryParameters,
  ) {
    if (queryParameters['ordertype']?.trim() != '1' || posts.length < 2) {
      return posts;
    }
    final firstPosts = <ThreadPost>[];
    final otherPosts = <ThreadPost>[];
    for (final post in posts) {
      if (post.isFirst || post.number == 1) {
        firstPosts.add(post);
      } else {
        otherPosts.add(post);
      }
    }
    if (firstPosts.isEmpty) {
      return posts;
    }
    return <ThreadPost>[...firstPosts, ...otherPosts];
  }

  String _rateReferer(ThreadDetailPageState? current, ThreadPost post) {
    final desktopUrl = current?.desktopUrl?.trim();
    final pid = post.pid.trim();
    if (desktopUrl != null && desktopUrl.isNotEmpty) {
      return pid.isEmpty ? desktopUrl : '$desktopUrl#pid$pid';
    }
    final tid = current?.tid.trim().isNotEmpty == true
        ? current!.tid.trim()
        : _args.tid;
    return pid.isEmpty
        ? '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid&mobile=2'
        : '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid&mobile=2#pid$pid';
  }

  ThreadRepository _readRepository() {
    return ref.read(threadRepositoryProvider);
  }

  ThreadActionNoticeCode _noticeCodeFor(ApiError error) {
    return switch (error.type) {
      ApiErrorType.unauthorized => ThreadActionNoticeCode.loginRequired,
      ApiErrorType.business => ThreadActionNoticeCode.failure,
      _ => ThreadActionNoticeCode.failure,
    };
  }

  ThreadUiErrorCode _errorCodeFor(ApiError error, ThreadUiErrorCode fallback) {
    return switch (error.type) {
      ApiErrorType.unauthorized => ThreadUiErrorCode.loginRequired,
      ApiErrorType.business => fallback,
      _ => fallback,
    };
  }

  Future<void> _invalidateCurrentThreadCache(String tid) async {
    final value = tid.trim();
    if (value.isEmpty) {
      return;
    }
    try {
      await ref
          .read(nativePageCacheInvalidationServiceProvider)
          .invalidateThread(value);
    } catch (_) {
      // Cache invalidation is best-effort; successful user actions should still
      // reload through the normal repository path if cache maintenance fails.
      return;
    }
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

  void _logNative(String stage, String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[ThreadDetail][native][$stage] $message');
  }

  String _formatQuery(Map<String, String> queryParameters) {
    if (queryParameters.isEmpty) {
      return '-';
    }
    return queryParameters.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
  }

  String _oneLine(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stackHead(StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isEmpty) {
      return '-';
    }
    return _oneLine(text.split('\n').first);
  }
}
