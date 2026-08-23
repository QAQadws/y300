import 'dart:async';

import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';

final forumWebViewControllerProvider =
    AsyncNotifierProvider.autoDispose<
      ForumWebViewController,
      ForumWebViewState
    >(ForumWebViewController.new);

final forumWebViewInitialUriProvider = Provider<Uri?>((ref) => null);

final forumWebViewPopOnRootBackProvider = Provider<bool>((ref) => false);

final forumWebViewHostPurposeProvider = Provider<ForumWebViewHostPurpose>(
  (ref) => ForumWebViewHostPurpose.browse,
);

final forumWebViewCompletionTargetProvider =
    Provider<ForumWebViewCompletionTarget?>((ref) => null);

class ForumWebViewController extends AsyncNotifier<ForumWebViewState> {
  late ForumWebViewNavigator _navigator;
  late ForumFavoriteRepository _favoriteRepository;
  late FavoriteForumDirectoryRepository _favoriteDirectoryRepository;
  ForumWebViewState? _lastKnownState;
  dynamic _keepAliveLink;
  int _pendingAsyncOperations = 0;
  bool _disposed = false;

  @override
  FutureOr<ForumWebViewState> build() {
    _disposed = false;
    _navigator = ref.read(forumWebViewNavigatorProvider);
    _favoriteRepository = ref.read(forumFavoriteRepositoryProvider);
    _favoriteDirectoryRepository = ref.read(
      favoriteForumDirectoryRepositoryProvider,
    );
    ref.onDispose(() {
      _disposed = true;
      _keepAliveLink?.close();
      _keepAliveLink = null;
    });
    final initialState = _initialState();
    _lastKnownState = initialState;
    return initialState;
  }

  ForumWebViewState _initialState() {
    final homeUri = _initialUri();
    return ForumWebViewState(
      currentUri: homeUri,
      pageKind: _navigator.classify(homeUri),
      searchScope: null,
      fid: null,
      tid: null,
      boardName: null,
      pageTitle: null,
      canGoBack: false,
      favoriteForums: const <FavoriteForumEntry>[],
      favoriteForumCapabilities: null,
      favoriteForumMetadata: null,
      currentFavoriteForum: null,
      isFavoriteMutationLoading: false,
      threadDetailMenu: null,
      isLoading: true,
      loadingProgress: 0,
    );
  }

  Uri _initialUri() {
    final initialUri = ref.read(forumWebViewInitialUriProvider);
    return initialUri ?? _navigator.homeUri;
  }

  ForumWebViewState get _currentState {
    if (_disposed) {
      return _lastKnownState ?? _initialState();
    }
    final currentState = state;
    final currentValue = currentState is AsyncData<ForumWebViewState>
        ? currentState.value
        : null;
    return currentValue ?? _lastKnownState ?? _initialState();
  }

  void onPageStarted(String rawUrl) {
    if (_disposed) {
      return;
    }
    final uri = _navigator.resolve(rawUrl);
    final current = _currentState;
    final pageKind = _navigator.classify(uri);
    final searchScope = _resolveSearchScope(
      pageKind: pageKind,
      uri: uri,
      current: current,
    );
    final fid = _resolveFidForPage(
      pageKind: pageKind,
      uri: uri,
      current: current,
      searchScope: searchScope,
    );
    final tid = _navigator.extractTid(uri);
    final currentFavoriteForum = _matchCurrentFavoriteForum(
      pageKind: pageKind,
      fid: fid,
      favoriteForums: current.favoriteForums,
    );
    final threadDetailMenu = _buildThreadDetailMenu(
      pageKind: pageKind,
      uri: uri,
    );
    final syncBoardName = _resolveSyncBoardName(pageKind: pageKind, fid: fid);
    _setState(
      current.copyWith(
        currentUri: uri,
        pageKind: pageKind,
        searchScope: searchScope,
        clearSearchScope: searchScope == null,
        fid: fid,
        clearFid: fid == null,
        tid: tid,
        clearTid: tid == null,
        boardName: syncBoardName,
        currentFavoriteForum: currentFavoriteForum,
        clearCurrentFavoriteForum: currentFavoriteForum == null,
        threadDetailMenu: threadDetailMenu,
        clearThreadDetailMenu: threadDetailMenu == null,
        isLoading: true,
        loadingProgress: 0,
      ),
    );
  }

  Future<void> onPageFinished({
    required String rawUrl,
    required String? pageTitle,
    required bool canGoBack,
    ForumThreadMenuSnapshot? threadMenuSnapshot,
  }) async {
    await _runKeptAlive(() async {
      if (_disposed) {
        return;
      }
      final uri = _navigator.resolve(rawUrl);
      final current = _currentState;
      final pageKind = _navigator.classify(uri);
      final searchScope = _resolveSearchScope(
        pageKind: pageKind,
        uri: uri,
        current: current,
      );
      final fid = _resolveFidForPage(
        pageKind: pageKind,
        uri: uri,
        current: current,
        searchScope: searchScope,
      );
      final tid = _navigator.extractTid(uri);
      final normalizedTitle = _normalizeText(pageTitle);
      final boardName = await _resolveBoardName(
        pageKind: pageKind,
        searchScope: searchScope,
        fid: fid,
        pageTitle: normalizedTitle,
      );
      if (_disposed) {
        return;
      }
      final latest = _currentState;
      final currentFavoriteForum = _matchCurrentFavoriteForum(
        pageKind: pageKind,
        fid: fid,
        favoriteForums: latest.favoriteForums,
      );
      final threadDetailMenu = _buildThreadDetailMenu(
        pageKind: pageKind,
        uri: uri,
        snapshot: threadMenuSnapshot,
      );
      _setState(
        latest.copyWith(
          currentUri: uri,
          pageKind: pageKind,
          searchScope: searchScope,
          clearSearchScope: searchScope == null,
          fid: fid,
          clearFid: fid == null,
          tid: tid,
          clearTid: tid == null,
          boardName: boardName,
          clearBoardName: boardName == null,
          pageTitle: pageKind == ForumWebViewPageKind.home
              ? null
              : normalizedTitle,
          clearPageTitle:
              pageKind == ForumWebViewPageKind.home || normalizedTitle == null,
          canGoBack: canGoBack,
          currentFavoriteForum: currentFavoriteForum,
          clearCurrentFavoriteForum: currentFavoriteForum == null,
          threadDetailMenu: threadDetailMenu,
          clearThreadDetailMenu: threadDetailMenu == null,
          isLoading: false,
          loadingProgress: 100,
        ),
      );
      if (pageKind == ForumWebViewPageKind.forumDisplay && fid != null) {
        unawaited(loadFavoriteForums());
      }
    });
  }

  void onProgress(int progress) {
    if (_disposed) {
      return;
    }
    final normalized = progress.clamp(0, 100).toInt();
    final current = _currentState;
    _setState(
      current.copyWith(
        loadingProgress: normalized,
        isLoading: normalized < 100 || current.isLoading,
      ),
    );
  }

  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  loadFavoriteForums() async {
    return _runKeptAlive(() async {
      final result = await _favoriteDirectoryRepository.load(
        const FavoriteForumDirectoryQuery(),
      );
      if (_disposed) {
        return result;
      }
      if (result
          case final DataReadSuccess<
                FavoriteForumDirectoryData,
                FavoriteForumDirectoryReadCapabilities
              >
              success) {
        final forums = success.data.items;
        final current = _currentState;
        final currentFavoriteForum = _matchCurrentFavoriteForum(
          pageKind: current.pageKind,
          fid: current.fid,
          favoriteForums: forums,
        );
        _setState(
          current.copyWith(
            favoriteForums: forums,
            favoriteForumCapabilities: success.capabilities,
            favoriteForumMetadata: success.metadata,
            currentFavoriteForum: currentFavoriteForum,
            clearCurrentFavoriteForum: currentFavoriteForum == null,
          ),
        );
      }
      return result;
    });
  }

  Future<ApiResult<ForumFavoriteMutationResult>> favoriteCurrentForum() async {
    final fid = _currentState.fid?.trim() ?? '';
    if (fid.isEmpty) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '当前版块 fid 缺失，无法收藏本版'),
      );
    }

    return _runKeptAlive(() async {
      _setFavoriteMutationLoading(true);
      final result = await _favoriteRepository.favoriteForum(fid: fid);
      if (result.isSuccess) {
        await loadFavoriteForums();
      }
      _setFavoriteMutationLoading(false);
      return result;
    });
  }

  Future<ApiResult<ForumFavoriteMutationResult>>
  unfavoriteCurrentForum() async {
    final currentFavoriteForum = _currentState.currentFavoriteForum;
    if (currentFavoriteForum == null) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '当前版块尚未收藏'),
      );
    }
    final capabilities = _currentState.favoriteForumCapabilities;
    final remoteFavoriteId = currentFavoriteForum.remoteFavoriteId?.trim();
    if (capabilities == null ||
        !capabilities.supports(
          FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        ) ||
        remoteFavoriteId == null ||
        remoteFavoriteId.isEmpty) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '找不到当前版块的收藏标识'),
      );
    }

    return _runKeptAlive(() async {
      _setFavoriteMutationLoading(true);
      final result = await _favoriteRepository.unfavoriteForum(
        favid: remoteFavoriteId,
      );
      if (result.isSuccess) {
        await loadFavoriteForums();
      }
      _setFavoriteMutationLoading(false);
      return result;
    });
  }

  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForumByFavid({
    required String favid,
  }) async {
    final remoteFavoriteId = favid.trim();
    final current = _currentState;
    final canUnfavorite =
        remoteFavoriteId.isNotEmpty &&
        current.favoriteForumCapabilities?.supports(
              FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
            ) ==
            true &&
        current.favoriteForums.any(
          (forum) => forum.remoteFavoriteId?.trim() == remoteFavoriteId,
        );
    if (!canUnfavorite) {
      return const ApiFailure<ForumFavoriteMutationResult>(
        ApiError(type: ApiErrorType.business, message: '找不到当前版块的收藏标识'),
      );
    }
    return _runKeptAlive(() async {
      _setFavoriteMutationLoading(true);
      final result = await _favoriteRepository.unfavoriteForum(
        favid: remoteFavoriteId,
      );
      if (result.isSuccess) {
        await loadFavoriteForums();
      }
      _setFavoriteMutationLoading(false);
      return result;
    });
  }

  ForumWebViewSearchScope? _resolveSearchScope({
    required ForumWebViewPageKind pageKind,
    required Uri uri,
    required ForumWebViewState current,
  }) {
    if (pageKind != ForumWebViewPageKind.search) {
      return null;
    }

    final extracted = _navigator.extractSearchScope(uri);
    if (extracted != null) {
      return extracted;
    }

    if (current.pageKind == ForumWebViewPageKind.search &&
        current.searchScope == ForumWebViewSearchScope.curForum &&
        _normalizeText(current.fid) != null) {
      return ForumWebViewSearchScope.curForum;
    }

    return ForumWebViewSearchScope.forum;
  }

  String? _resolveFidForPage({
    required ForumWebViewPageKind pageKind,
    required Uri uri,
    required ForumWebViewState current,
    required ForumWebViewSearchScope? searchScope,
  }) {
    if (pageKind == ForumWebViewPageKind.search) {
      if (searchScope != ForumWebViewSearchScope.curForum) {
        return null;
      }
      return _navigator.extractSearchFid(uri) ?? current.fid;
    }

    final extracted = _navigator.extractFid(uri);
    if (pageKind == ForumWebViewPageKind.threadDetail) {
      return extracted ?? current.fid;
    }
    return extracted;
  }

  Future<String?> _resolveBoardName({
    required ForumWebViewPageKind pageKind,
    required ForumWebViewSearchScope? searchScope,
    required String? fid,
    required String? pageTitle,
  }) async {
    if (pageKind == ForumWebViewPageKind.home) {
      return null;
    }

    if (pageKind == ForumWebViewPageKind.search) {
      if (searchScope != ForumWebViewSearchScope.curForum || fid == null) {
        return null;
      }
      try {
        final lookup = await ref.read(forumTagLookupProvider.future);
        return _normalizeText(lookup.findBoard(fid: fid)?.name);
      } catch (_) {
        return null;
      }
    }

    if (fid != null) {
      try {
        final lookup = await ref.read(forumTagLookupProvider.future);
        final boardName = _normalizeText(lookup.findBoard(fid: fid)?.name);
        if (boardName != null) {
          return boardName;
        }
      } catch (_) {
        // 标签加载失败时降级到页面标题/基础文案，不阻断 WebView 主流程。
      }
    }

    if (pageTitle != null) {
      return pageTitle;
    }
    return null;
  }

  /// Synchronously resolves board name from cached [forumTagLookupProvider] data.
  ///
  /// Returns null for home pages, or when the lookup has not been cached yet.
  /// This ensures the AppBar title and back button appear in the same frame,
  /// avoiding a two-step visual flicker when navigating from home to a forum.
  String? _resolveSyncBoardName({
    required ForumWebViewPageKind pageKind,
    required String? fid,
  }) {
    if (pageKind == ForumWebViewPageKind.home) return null;
    if (fid == null) return null;
    final lookup = ref.read(forumTagLookupProvider).value;
    if (lookup == null) return null;
    return _normalizeText(lookup.findBoard(fid: fid)?.name);
  }

  String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  FavoriteForumEntry? _matchCurrentFavoriteForum({
    required ForumWebViewPageKind pageKind,
    required String? fid,
    required List<FavoriteForumEntry> favoriteForums,
  }) {
    if (pageKind != ForumWebViewPageKind.forumDisplay || fid == null) {
      return null;
    }
    final normalizedFid = fid.trim();
    if (normalizedFid.isEmpty) {
      return null;
    }
    for (final forum in favoriteForums) {
      if (forum.fid.trim() == normalizedFid) {
        return forum;
      }
    }
    return null;
  }

  ForumThreadDetailMenuState? _buildThreadDetailMenu({
    required ForumWebViewPageKind pageKind,
    required Uri uri,
    ForumThreadMenuSnapshot? snapshot,
  }) {
    if (pageKind != ForumWebViewPageKind.threadDetail) {
      return null;
    }

    final isAuthorOnly = _navigator.extractAuthorId(uri) != null;
    final isReverseOrder = _navigator.isReverseOrder(uri);
    return ForumThreadDetailMenuState(
      isAuthorOnly: isAuthorOnly,
      isReverseOrder: isReverseOrder,
      authorOnlyUri: snapshot?.authorOnlyUri,
      normalThreadUri:
          snapshot?.normalThreadUri ??
          (isAuthorOnly ? _navigator.buildNormalThreadUri(uri) : null),
      reverseOrderUri:
          snapshot?.reverseOrderUri ?? _navigator.buildReverseOrderUri(uri),
      normalOrderUri:
          snapshot?.normalOrderUri ?? _navigator.buildNormalOrderUri(uri),
    );
  }

  void _setFavoriteMutationLoading(bool isLoading) {
    if (_disposed) {
      return;
    }
    final current = _currentState;
    _setState(current.copyWith(isFavoriteMutationLoading: isLoading));
  }

  void _setState(ForumWebViewState nextState) {
    _lastKnownState = nextState;
    if (_disposed) {
      return;
    }
    state = AsyncData(nextState);
  }

  Future<T> _runKeptAlive<T>(Future<T> Function() action) async {
    final shouldKeepAlive = !_disposed;
    if (shouldKeepAlive) {
      _pendingAsyncOperations += 1;
      _keepAliveLink ??= ref.keepAlive();
    }
    try {
      return await action();
    } finally {
      if (shouldKeepAlive) {
        _pendingAsyncOperations -= 1;
        if (_pendingAsyncOperations == 0) {
          _keepAliveLink?.close();
          _keepAliveLink = null;
        }
      }
    }
  }
}
