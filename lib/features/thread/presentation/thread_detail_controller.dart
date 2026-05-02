import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
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
    return other is ThreadDetailArgs && other.tid == tid && other.subject == subject;
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
    return _loadPage(page: 1, previous: const <ThreadPost>[]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadPage(page: 1, previous: const <ThreadPost>[]),
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
    );

    state = result.when(
      success: (data) {
        final merged = <ThreadPost>[...current.posts, ...data.posts];
        return AsyncData(
          current.copyWith(
            subject: data.subject.isNotEmpty ? data.subject : current.subject,
            currentPage: data.currentPage,
            hasMore: data.hasMore,
            isLoadingMore: false,
            posts: merged,
            clearError: true,
          ),
        );
      },
      failure: (error) {
        return AsyncData(
          current.copyWith(
            isLoadingMore: false,
            errorMessage: error.message,
          ),
        );
      },
    );
  }

  Future<void> addToShelf() async {
    final current = state.value;
    if (current == null || current.isComicActionLoading || !current.comicCandidateInfo.isCandidate) {
      return;
    }

    state = AsyncData(current.copyWith(isComicActionLoading: true, clearError: true));
    final comicId = _buildComicId(tid: _args.tid);

    try {
      await _readComicRepository().addToShelf(
        comicId: comicId,
        tid: _args.tid,
        fid: current.fid,
        title: current.subject,
        parsedPost: current.parsedComicPost,
      );

      final updated = state.value ?? current;
      state = AsyncData(
        updated.copyWith(
          isComicActionLoading: false,
          isInShelf: true,
        ),
      );
    } catch (error) {
      final updated = state.value ?? current;
      state = AsyncData(
        updated.copyWith(
          isComicActionLoading: false,
          errorMessage: '加入书架失败：$error',
        ),
      );
    }
  }

  Future<ThreadDetailPageState> _loadPage({
    required int page,
    required List<ThreadPost> previous,
  }) async {
    final result = await _readRepository().getThreadDetail(tid: _args.tid, page: page);

    if (result case ApiSuccess<ThreadDetailData>(:final data)) {
      final merged = page == 1 ? data.posts : <ThreadPost>[...previous, ...data.posts];
      final aggregation = ref.read(comicPostAggregationServiceProvider).build(merged);
      final comicMeta = _detectAndParseComic(
        fid: data.fid,
        subject: data.subject.isNotEmpty ? data.subject : _args.subject,
        message: aggregation.detectionMessage,
        parseMessage: aggregation.parseMessage,
      );
      final comicId = _buildComicId(tid: _args.tid);
      final isInShelf = await _readComicRepository().isInShelf(comicId: comicId);

      return ThreadDetailPageState(
        tid: _args.tid,
        fid: data.fid,
        subject: data.subject.isNotEmpty ? data.subject : _args.subject,
        currentPage: data.currentPage,
        hasMore: data.hasMore,
        isLoadingInitial: false,
        isLoadingMore: false,
        posts: merged,
        comicCandidateInfo: comicMeta.$1,
        parsedComicPost: comicMeta.$2,
        isInShelf: isInShelf,
        isComicActionLoading: false,
      );
    }

    final error = (result as ApiFailure<ThreadDetailData>).error;
    return ThreadDetailPageState(
      tid: _args.tid,
      fid: '',
      subject: _args.subject,
      currentPage: page == 1 ? 0 : page,
      hasMore: false,
      isLoadingInitial: false,
      isLoadingMore: false,
      posts: previous,
      comicCandidateInfo: ComicCandidateInfo.notCandidate,
      parsedComicPost: ParsedComicPost.empty,
      isInShelf: false,
      isComicActionLoading: false,
      errorMessage: error.message,
    );
  }

  ThreadRepository _readRepository() {
    return ref.read(threadRepositoryProvider);
  }

  ComicRepository _readComicRepository() {
    return ref.read(comicRepositoryProvider);
  }

  (ComicCandidateInfo, ParsedComicPost) _detectAndParseComic({
    required String fid,
    required String subject,
    required String message,
    required String parseMessage,
  }) {
    if (message.isEmpty) {
      return (ComicCandidateInfo.notCandidate, ParsedComicPost.empty);
    }

    final detector = ref.read(comicDetectorProvider);
    final parser = ref.read(comicParserServiceProvider);
    final subjectParser = ref.read(comicSubjectParserProvider);
    final candidate = detector.detect(fid: fid, subject: subject, message: message);

    if (!candidate.isCandidate) {
      return (candidate, ParsedComicPost.empty);
    }

    final parsed = parser.parse(message: parseMessage).copyWith(
          subjectMetadata: subjectParser.parse(subject),
        );
    return (candidate, parsed);
  }

  String _buildComicId({required String tid}) {
    return 'yamibo:$tid';
  }

}
