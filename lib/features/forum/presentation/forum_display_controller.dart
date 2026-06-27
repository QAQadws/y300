import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/domain/cache_load_policy.dart';
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
    return other is ForumDisplayArgs &&
        other.fid == fid &&
        other.title == title;
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
    return _loadQuery(ForumDisplayQuery.initial(fid: _args.fid));
  }

  Future<void> refresh({bool forceNetwork = false}) async {
    final query =
        state.value?.query ?? ForumDisplayQuery.initial(fid: _args.fid);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadQuery(
        query,
        cachePolicy: forceNetwork
            ? CacheLoadPolicy.networkFirst
            : CacheLoadPolicy.cacheFirst,
      ),
    );
  }

  Future<void> loadMore() async {
    await loadNextPage();
  }

  Future<void> loadNextPage() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }
    final query = _queryFromUrl(
      current.nextPageUrl,
      fallback: current.query.copyWithPage(current.currentPage + 1),
    );
    await _replaceWithQuery(query, current: current);
  }

  Future<void> loadPreviousPage() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || current.currentPage <= 1) {
      return;
    }
    final query = _queryFromUrl(
      current.previousPageUrl,
      fallback: current.query.copyWithPage(current.currentPage - 1),
    );
    await _replaceWithQuery(query, current: current);
  }

  Future<void> loadPageNumber(int page) async {
    if (page < 1) {
      return;
    }
    final current = state.value;
    final query = (current?.query ?? ForumDisplayQuery.initial(fid: _args.fid))
        .copyWithPage(page);
    await _replaceWithQuery(query, current: current);
  }

  Future<void> openFilter(ForumDisplayFilterItem item) async {
    await openForumDisplayUrl(item.url);
  }

  Future<void> openThreadTag(ForumThreadSummary thread) async {
    final url = thread.sourceTagUrl;
    if (url == null || url.trim().isEmpty) {
      return;
    }
    await openForumDisplayUrl(url);
  }

  Future<void> openForumDisplayUrl(String url) async {
    final current = state.value;
    final query = ForumDisplayQuery.fromUrl(
      url,
      fallbackFid: current?.fid ?? _args.fid,
    );
    await _replaceWithQuery(query, current: current);
  }

  Future<void> _replaceWithQuery(
    ForumDisplayQuery query, {
    required ForumDisplayPageState? current,
  }) async {
    if (current == null) {
      state = const AsyncLoading();
    } else {
      state = AsyncData(
        current.copyWith(isLoadingMore: true, clearError: true),
      );
    }
    state = await AsyncValue.guard(() => _loadQuery(query));
  }

  Future<ForumDisplayPageState> _loadQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final result = await _readRepository().getForumDisplayByQuery(
      query,
      cachePolicy: cachePolicy,
    );
    if (result case ApiSuccess<ForumDisplayData>(:final data)) {
      final mappedThreads = await _attachSourceTagNames(data);
      final effectiveQuery = query.copyWithPage(data.currentPage);
      return ForumDisplayPageState(
        fid: data.fid.isNotEmpty ? data.fid : query.fid,
        title: data.forumName.isNotEmpty ? data.forumName : _args.title,
        currentPage: data.currentPage,
        hasMore: data.hasMore,
        isLoadingInitial: false,
        isLoadingMore: false,
        threads: mappedThreads,
        query: effectiveQuery,
        headImageUrl: data.headImageUrl,
        forumIconUrl: data.forumIconUrl,
        todayPosts: data.todayPosts,
        totalThreads: data.totalThreads,
        rank: data.rank,
        primaryFilters: data.primaryFilters,
        typeFilters: data.typeFilters,
        subForums: data.subForums,
        topEntries: data.topEntries,
        previousPageUrl: data.previousPageUrl,
        nextPageUrl: data.nextPageUrl,
        lastPage: data.lastPage,
      );
    }

    final error = (result as ApiFailure<ForumDisplayData>).error;
    return ForumDisplayPageState(
      fid: query.fid,
      title: _args.title,
      currentPage: query.page,
      hasMore: false,
      isLoadingInitial: false,
      isLoadingMore: false,
      threads: const <ForumThreadSummary>[],
      query: query,
      errorMessage: error.message,
    );
  }

  ForumDisplayQuery _queryFromUrl(
    String? url, {
    required ForumDisplayQuery fallback,
  }) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return ForumDisplayQuery.fromUrl(
      value,
      fallbackFid: fallback.fid,
      fallbackPage: fallback.page,
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
        .map((thread) {
          final parsedName = thread.sourceTagName?.trim();
          if (parsedName != null && parsedName.isNotEmpty) {
            return thread;
          }
          return thread.copyWith(
            sourceTagName: lookup.findName(
              fid: data.fid,
              typeid: thread.typeid,
            ),
          );
        })
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
