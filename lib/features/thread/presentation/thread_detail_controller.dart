import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/comic/data/services/comic_parser_service.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/thread/data/providers/thread_favorite_providers.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_post_comment_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_post_rate_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_poll_vote_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
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

  Future<void> refreshAfterMutation() async {
    final current = state.value;
    if (current != null) {
      await _invalidateCurrentThreadCache(current.tid);
    }
    await refresh();
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
    if (current == null) {
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
    if (current == null || !current.isOnlyAuthorView) {
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
    if (current == null) {
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
    if (current == null || !current.isReverseOrderView) {
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
    if (current == null || current.isPollVoteSubmitting || !poll.canVote) {
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
        pollVoteHint: message.isEmpty ? '投票成功' : message,
        selectedPollOptionIds: const <String>{},
        isPollVoteSubmitting: false,
      ),
    );
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
        ),
      );
    }
  }

  Future<ThreadDetailPageState> _loadPage({
    required int page,
    required List<ThreadPost> previous,
    required Map<String, String> queryParameters,
  }) async {
    _logNative(
      'controller_load',
      'tid=${_args.tid} page=$page previous=${previous.length} '
          'query=${_formatQuery(queryParameters)}',
    );
    final result = await _readRepository().getThreadDetail(
      tid: _args.tid,
      page: page,
      queryParameters: queryParameters,
    );

    if (result case ApiSuccess<ThreadDetailData>(:final data)) {
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

        stage = 'aggregation';
        final aggregationStopwatch = Stopwatch()..start();
        _logNative(
          'controller_aggregation_start',
          'tid=${_args.tid} posts=${merged.length} '
              'totalMessageLength=${_totalMessageLength(merged)} '
              'firstMessageLength=${merged.isEmpty ? 0 : merged.first.message.length} '
              'rawAttachmentImages=${_totalAttachmentImages(merged)}',
        );
        final aggregation = ref
            .read(comicPostAggregationServiceProvider)
            .build(merged);
        aggregationStopwatch.stop();
        _logNative(
          'controller_aggregation_done',
          'tid=${_args.tid} elapsedMs=${aggregationStopwatch.elapsedMilliseconds} '
              'detectionLength=${aggregation.detectionMessage.length} '
              'parseMessageLength=${aggregation.parseMessage.length} '
              'attachmentImageUrls=${aggregation.attachmentImageUrls.length} '
              'usedSecondFloor=${aggregation.usedSecondFloor} '
              'secondFloorPid=${aggregation.secondFloorPid ?? '-'}',
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

        stage = 'comic_parse';
        if (contentKind == ThreadContentKind.comic) {
          _logNative(
            'controller_comic_parse_start',
            'tid=${_args.tid} subjectLength=${subject.length} '
                'parseMessageLength=${aggregation.parseMessage.length} '
                'attachmentImageUrls=${aggregation.attachmentImageUrls.length}',
          );
        } else {
          _logNative(
            'controller_comic_parse_skipped',
            'tid=${_args.tid} kind=${contentKind.name}',
          );
        }
        final comicParseStopwatch = Stopwatch()..start();
        final comicMeta = _parseComicWhenTagged(
          isComic: contentKind == ThreadContentKind.comic,
          subject: subject,
          parseMessage: aggregation.parseMessage,
          attachmentImageUrls: aggregation.attachmentImageUrls,
        );
        comicParseStopwatch.stop();
        _logNative(
          'controller_comic_parse_done',
          'tid=${_args.tid} elapsedMs=${comicParseStopwatch.elapsedMilliseconds} '
              'candidate=${comicMeta.$1.isCandidate} '
              'score=${comicMeta.$1.score} '
              'imageUrls=${comicMeta.$2.imageUrls.length} '
              'episodeLinks=${comicMeta.$2.episodeLinks.length} '
              'catalog=${comicMeta.$2.catalogUrl?.trim().isNotEmpty == true}',
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
        );
      }
    }

    final error = (result as ApiFailure<ThreadDetailData>).error;
    _logNative(
      'controller_failure',
      'tid=${_args.tid} page=$page previous=${previous.length} '
          'type=${error.type.name} status=${error.statusCode ?? '-'} '
          'message=${_oneLine(error.message)}',
    );
    return _failureState(
      page: page,
      previous: previous,
      queryParameters: queryParameters,
      message: error.message,
    );
  }

  ThreadDetailPageState _failureState({
    required int page,
    required List<ThreadPost> previous,
    required Map<String, String> queryParameters,
    required String message,
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
      comicCandidateInfo: ComicCandidateInfo.notCandidate,
      parsedComicPost: ParsedComicPost.empty,
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

  int _totalMessageLength(List<ThreadPost> posts) {
    return posts.fold<int>(0, (total, post) => total + post.message.length);
  }

  int _totalAttachmentImages(List<ThreadPost> posts) {
    return posts.fold<int>(
      0,
      (total, post) => total + post.attachmentImages.length,
    );
  }

  String _stackHead(StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isEmpty) {
      return '-';
    }
    return _oneLine(text.split('\n').first);
  }
}
