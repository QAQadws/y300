import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<ThreadDetailPageState> _loadPage({
    required int page,
    required List<ThreadPost> previous,
  }) async {
    final result = await _readRepository().getThreadDetail(tid: _args.tid, page: page);

    return result.when(
      success: (data) {
        final merged = page == 1 ? data.posts : <ThreadPost>[...previous, ...data.posts];
        return ThreadDetailPageState(
          tid: _args.tid,
          subject: data.subject.isNotEmpty ? data.subject : _args.subject,
          currentPage: data.currentPage,
          hasMore: data.hasMore,
          isLoadingInitial: false,
          isLoadingMore: false,
          posts: merged,
        );
      },
      failure: (error) {
        return ThreadDetailPageState(
          tid: _args.tid,
          subject: _args.subject,
          currentPage: page == 1 ? 0 : page,
          hasMore: false,
          isLoadingInitial: false,
          isLoadingMore: false,
          posts: previous,
          errorMessage: error.message,
        );
      },
    );
  }

  ThreadRepository _readRepository() {
    return ref.read(threadRepositoryProvider);
  }
}
