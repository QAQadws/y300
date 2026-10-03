import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/data/providers/forum_display_repository_providers.dart';
import 'package:y300/features/forum/domain/services/forum_chrome_image_adapter.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';

class ForumDisplayArgs {
  const ForumDisplayArgs({
    required this.fid,
    this.title = '',
    this.initialPage = 1,
  });

  final String fid;
  final String title;
  final int initialPage;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ForumDisplayArgs &&
        other.fid == fid &&
        other.title == title &&
        other.initialPage == initialPage;
  }

  @override
  int get hashCode => Object.hash(fid, title, initialPage);
}

final forumDisplayControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ForumDisplayController, ForumDisplayPageState, ForumDisplayArgs>(
      (args) => ForumDisplayController(args),
    );

/// forumdisplay 分页控制器，统一管理首屏加载、加载更多和错误状态。
class ForumDisplayController extends AsyncNotifier<ForumDisplayPageState> {
  ForumDisplayController(this._args);

  final ForumDisplayArgs _args;
  int _requestGeneration = 0;

  @override
  FutureOr<ForumDisplayPageState> build() async {
    final scope = ref.watch(yamiboForumSourceScopeProvider);
    final repository = ref.watch(forumDisplayRepositoryProvider);
    _requestGeneration++;
    ref.onDispose(() => _requestGeneration++);
    return _loadQuery(
      ForumDisplayQuery.initial(fid: _args.fid).copyWithPage(_args.initialPage),
      scope: scope,
      repository: repository,
    );
  }

  Future<void> refresh({bool forceNetwork = false}) async {
    final scope = ref.read(yamiboForumSourceScopeProvider);
    final repository = ref.read(forumDisplayRepositoryProvider);
    final generation = ++_requestGeneration;
    final query =
        state.value?.query ?? ForumDisplayQuery.initial(fid: _args.fid);
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => _loadQuery(
        query,
        scope: scope,
        repository: repository,
        cachePolicy: forceNetwork
            ? CacheLoadPolicy.networkFirst
            : CacheLoadPolicy.cacheFirst,
      ),
    );
    if (_isCurrent(scope, generation)) state = next;
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
    final scope = ref.read(yamiboForumSourceScopeProvider);
    final repository = ref.read(forumDisplayRepositoryProvider);
    final generation = ++_requestGeneration;
    if (current == null) {
      state = const AsyncLoading();
    } else {
      state = AsyncData(
        current.copyWith(isLoadingMore: true, clearError: true),
      );
    }
    final next = await AsyncValue.guard(
      () => _loadQuery(query, scope: scope, repository: repository),
    );
    if (_isCurrent(scope, generation)) state = next;
  }

  Future<ForumDisplayPageState> _loadQuery(
    ForumDisplayQuery query, {
    required Y300ForumSourceScope scope,
    required ForumDisplayRepository repository,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    _ensureCurrent(scope);
    final result = await repository.getForumDisplayByQuery(
      query,
      cachePolicy: cachePolicy,
    );
    _ensureCurrent(scope);
    if (result
        case DataReadSuccess<ForumDisplayData, ForumDisplayReadCapabilities>(
          :final data,
          :final capabilities,
          :final metadata,
        )) {
      final mappedThreads = await _attachSourceTagNames(data);
      _ensureCurrent(scope);
      final effectiveQuery = query.copyWithPage(data.currentPage);
      final effectiveFid = data.fid.isNotEmpty ? data.fid : query.fid;
      final headImageDimensions = await _readHeadImageDimensions(
        fid: effectiveFid,
        imageUrl: data.headImageUrl,
      );
      _ensureCurrent(scope);
      return ForumDisplayPageState(
        fid: effectiveFid,
        title: data.forumName.isNotEmpty ? data.forumName : _args.title,
        currentPage: data.currentPage,
        hasMore: data.hasMore,
        isLoadingInitial: false,
        isLoadingMore: false,
        threads: mappedThreads,
        query: effectiveQuery,
        headImageUrl: data.headImageUrl,
        headImageDimensions: headImageDimensions,
        forumIconUrl: data.forumIconUrl,
        todayPosts: data.todayPosts,
        totalThreads: data.totalThreads,
        rank: data.rank,
        primaryFilters: capabilities.supports(ForumDisplayCapability.filters)
            ? data.primaryFilters
            : const <ForumDisplayFilterItem>[],
        typeFilters: capabilities.supports(ForumDisplayCapability.filters)
            ? data.typeFilters
            : const <ForumDisplayFilterItem>[],
        subForums: capabilities.supports(ForumDisplayCapability.subForums)
            ? data.subForums
            : const <ForumDisplaySubForum>[],
        topEntries: capabilities.supports(ForumDisplayCapability.topEntries)
            ? data.topEntries
            : const <ForumDisplayTopEntry>[],
        previousPageUrl: data.previousPageUrl,
        nextPageUrl: data.nextPageUrl,
        lastPage: capabilities.supports(ForumDisplayCapability.exactPagination)
            ? data.lastPage
            : null,
        favoriteAction:
            capabilities.supports(ForumDisplayCapability.favoriteState)
            ? data.favoriteAction
            : ForumDisplayFavoriteAction.unknown,
        capabilities: capabilities,
        readMetadata: metadata,
      );
    }

    final failure =
        (result
                as DataReadFailure<
                  ForumDisplayData,
                  ForumDisplayReadCapabilities
                >)
            .diagnosticMessage;
    return ForumDisplayPageState(
      fid: query.fid,
      title: _args.title,
      currentPage: query.page,
      hasMore: false,
      isLoadingInitial: false,
      isLoadingMore: false,
      threads: const <ForumThreadSummary>[],
      query: query,
      failure: ForumDisplayFailure(
        code: ForumDisplayFailureCode.loadFailed,
        detail: failure,
      ),
      errorMessage: failure,
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
    if (!data.threads.any(
      (thread) =>
          thread.typeid.trim().isNotEmpty &&
          (thread.sourceTagName?.trim().isEmpty ?? true),
    )) {
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

  Future<ForumImageDimensions?> _readHeadImageDimensions({
    required String fid,
    required String? imageUrl,
  }) async {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    final spec = const ForumChromeImageAdapter().headImage(
      fid: fid,
      imageUrl: url,
    );
    if (spec == null) {
      return null;
    }
    try {
      return await ref
          .read(forumImageDimensionIndexProvider)
          .getLastKnownBySpec(spec);
    } catch (_) {
      // Layout metadata is an optional local hint and must never prevent the
      // forum page from publishing otherwise valid network data.
      return null;
    }
  }

  bool _isCurrent(Y300ForumSourceScope scope, int generation) =>
      ref.mounted && scope.isCurrent && generation == _requestGeneration;

  void _ensureCurrent(Y300ForumSourceScope scope) {
    if (!ref.mounted || !scope.isCurrent) {
      throw StateError('forum_source_scope_expired');
    }
  }
}
