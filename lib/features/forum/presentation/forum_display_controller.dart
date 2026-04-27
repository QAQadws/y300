import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/data/forum_display_repository.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';

class ForumDisplayArgs {
  const ForumDisplayArgs({required this.fid, this.title = ''});

  final String fid;
  final String title;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ForumDisplayArgs && other.fid == fid && other.title == title;
  }

  @override
  int get hashCode => Object.hash(fid, title);
}

final forumDisplayControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ForumDisplayController, ForumDisplayPageState, ForumDisplayArgs>(
      (args) => ForumDisplayController(args),
    );

/// forumdisplay 分页控制器，统一管理首屏加载、加载更多和错误状态。
class ForumDisplayController extends AsyncNotifier<ForumDisplayPageState> {
  ForumDisplayController(this._args);

  final ForumDisplayArgs _args;

  @override
  FutureOr<ForumDisplayPageState> build() async {
    return _loadPage(page: 1, previous: const <ForumThreadSummary>[]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadPage(page: 1, previous: const <ForumThreadSummary>[]),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    final result = await _readRepository().getForumDisplay(
      fid: _args.fid,
      page: current.currentPage + 1,
    );

    state = result.when(
      success: (data) {
        final merged = <ForumThreadSummary>[...current.threads, ...data.threads];
        return AsyncData(
          current.copyWith(
            title: data.forumName.isNotEmpty ? data.forumName : current.title,
            currentPage: data.currentPage,
            hasMore: data.hasMore,
            isLoadingMore: false,
            threads: merged,
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

  Future<ForumDisplayPageState> _loadPage({
    required int page,
    required List<ForumThreadSummary> previous,
  }) async {
    final result = await _readRepository().getForumDisplay(fid: _args.fid, page: page);

    return result.when(
      success: (data) {
        final merged = page == 1 ? data.threads : <ForumThreadSummary>[...previous, ...data.threads];
        return ForumDisplayPageState(
          fid: _args.fid,
          title: data.forumName.isNotEmpty ? data.forumName : _args.title,
          currentPage: data.currentPage,
          hasMore: data.hasMore,
          isLoadingInitial: false,
          isLoadingMore: false,
          threads: merged,
        );
      },
      failure: (error) {
        return ForumDisplayPageState(
          fid: _args.fid,
          title: _args.title,
          currentPage: page == 1 ? 0 : page,
          hasMore: false,
          isLoadingInitial: false,
          isLoadingMore: false,
          threads: previous,
          errorMessage: error.message,
        );
      },
    );
  }

  ForumDisplayRepository _readRepository() {
    return ref.read(forumDisplayRepositoryProvider);
  }
}
