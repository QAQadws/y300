import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/data/forum_display_repository.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';

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

    if (result case ApiSuccess<ForumDisplayData>(:final data)) {
      final mappedThreads = await _attachSourceTagNames(data);
      final merged = <ForumThreadSummary>[...current.threads, ...mappedThreads];
      state = AsyncData(
        current.copyWith(
          title: data.forumName.isNotEmpty ? data.forumName : current.title,
          currentPage: data.currentPage,
          hasMore: data.hasMore,
          isLoadingMore: false,
          threads: merged,
          clearError: true,
        ),
      );
      return;
    }

    final error = (result as ApiFailure<ForumDisplayData>).error;
    state = AsyncData(
      current.copyWith(
        isLoadingMore: false,
        errorMessage: error.message,
      ),
    );
  }

  Future<ForumDisplayPageState> _loadPage({
    required int page,
    required List<ForumThreadSummary> previous,
  }) async {
    final result = await _readRepository().getForumDisplay(fid: _args.fid, page: page);

    if (result case ApiSuccess<ForumDisplayData>(:final data)) {
      final mappedThreads = await _attachSourceTagNames(data);
      final merged = page == 1
          ? mappedThreads
          : <ForumThreadSummary>[...previous, ...mappedThreads];
      return ForumDisplayPageState(
        fid: _args.fid,
        title: data.forumName.isNotEmpty ? data.forumName : _args.title,
        currentPage: data.currentPage,
        hasMore: data.hasMore,
        isLoadingInitial: false,
        isLoadingMore: false,
        threads: merged,
      );
    }

    final error = (result as ApiFailure<ForumDisplayData>).error;
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
  }

  Future<List<ForumThreadSummary>> _attachSourceTagNames(
    ForumDisplayData data,
  ) async {
    if (!data.threads.any((thread) => thread.typeid.trim().isNotEmpty)) {
      return data.threads;
    }
    final lookup = await _readTagLookup();
    if (lookup == null) {
      return data.threads;
    }
    return data.threads
        .map(
          (thread) => thread.copyWith(
            sourceTagName: lookup.findName(
              fid: data.fid,
              typeid: thread.typeid,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<ForumTagLookup?> _readTagLookup() async {
    try {
      return await ref.read(forumTagLookupProvider.future);
    } catch (_) {
      return null;
    }
  }

  ForumDisplayRepository _readRepository() {
    return ref.read(forumDisplayRepositoryProvider);
  }
}
