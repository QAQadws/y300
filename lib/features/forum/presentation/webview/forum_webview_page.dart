import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';

class ForumWebViewPage extends ConsumerStatefulWidget {
  const ForumWebViewPage({super.key});

  @override
  ConsumerState<ForumWebViewPage> createState() => _ForumWebViewPageState();
}

class _ForumWebViewPageState extends ConsumerState<ForumWebViewPage> {
  static const String _homeUnfavoriteAction = 'home-unfavorite';
  static const String _forumFavoriteAction = 'forum-favorite';
  static const String _forumUnfavoriteAction = 'forum-unfavorite';
  static const String _searchGoHomeAction = 'search-go-home';

  bool _didScheduleInitialization = false;
  int _navigationGeneration = 0;
  Timer? _delayedCleanupTimer;

  @override
  void dispose() {
    _delayedCleanupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigator = ref.watch(forumWebViewNavigatorProvider);
    final asyncState = ref.watch(forumWebViewControllerProvider);
    final homeUri = navigator.homeUri;
    final state =
        asyncState.asData?.value ??
        ForumWebViewState(
          currentUri: homeUri,
          pageKind: navigator.classify(homeUri),
          searchScope: null,
          fid: null,
          tid: null,
          boardName: null,
          pageTitle: null,
          canGoBack: false,
          favoriteForums: const <FavoriteForum>[],
          currentFavoriteForum: null,
          isFavoriteMutationLoading: false,
          isLoading: true,
          loadingProgress: 0,
        );
    final driver = ref.watch(forumWebViewDriverProvider);

    if (!_didScheduleInitialization) {
      _didScheduleInitialization = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_initialize(driver));
      });
    }

    return Scaffold(
      key: const Key('forum-webview-page'),
      appBar: _buildAppBar(context, state, driver),
      body: Column(
        children: [
          if (state.isLoading && state.loadingProgress < 100)
            LinearProgressIndicator(
              value: state.loadingProgress.clamp(0, 99).toDouble() / 100,
            ),
          Expanded(
            child: driver.buildWidget(
              key: const Key('forum-webview-surface'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initialize(ForumWebViewDriver driver) async {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    await driver.initialize(
      callbacks: ForumWebViewCallbacks(
        onPageStarted: _handlePageStarted,
        onPageFinished: _handlePageFinished,
        onProgress: _handleProgress,
        onNavigationRequest: _handleNavigationRequest,
      ),
    );
    if (!mounted) {
      return;
    }

    final cookieHeader = await ref
        .read(cookieStoreProvider)
        .readCookieHeader(navigator.homeUri);
    if (!mounted) {
      return;
    }

    await driver.seedCookies(
      domain: navigator.homeUri.host,
      cookies: _parseCookieHeader(cookieHeader),
    );
    if (!mounted) {
      return;
    }

    await driver.load(navigator.homeUri);
  }

  void _handlePageStarted(String url) {
    if (!mounted) {
      return;
    }
    _delayedCleanupTimer?.cancel();
    _delayedCleanupTimer = null;
    _navigationGeneration += 1;
    ref.read(forumWebViewControllerProvider.notifier).onPageStarted(url);
  }

  Future<void> _handlePageFinished(String url) async {
    if (!mounted) {
      return;
    }
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final injector = ref.read(forumWebViewScriptInjectorProvider);
    final driver = ref.read(forumWebViewDriverProvider);

    final pageTitle = await _readPageTitle(driver);
    final canGoBack = await _readCanGoBack(driver);
    if (!mounted) {
      return;
    }
    await ref.read(forumWebViewControllerProvider.notifier).onPageFinished(
          rawUrl: url,
          pageTitle: pageTitle,
          canGoBack: canGoBack,
        );
    final uri = navigator.resolve(url);
    if (!navigator.isManagedSite(uri)) {
      return;
    }

    final generation = _navigationGeneration;
    await injector.cleanChrome(driver);

    _delayedCleanupTimer?.cancel();
    _delayedCleanupTimer = Timer(
      const Duration(milliseconds: 300),
      () async {
        if (!mounted || generation != _navigationGeneration) {
          return;
        }
        final currentUri = ref
            .read(forumWebViewControllerProvider)
            .asData
            ?.value
            .currentUri;
        if (currentUri != uri) {
          return;
        }
        await injector.cleanChrome(driver);
      },
    );
  }

  void _handleProgress(int progress) {
    if (!mounted) {
      return;
    }
    ref.read(forumWebViewControllerProvider.notifier).onProgress(progress);
  }

  FutureOr<ForumWebViewNavigationDecision> _handleNavigationRequest(
    String _,
  ) {
    return ForumWebViewNavigationDecision.navigate;
  }

  Map<String, String> _parseCookieHeader(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const <String, String>{};
    }

    final output = <String, String>{};
    for (final rawSegment in header.split(';')) {
      final segment = rawSegment.trim();
      if (segment.isEmpty || !segment.contains('=')) {
        continue;
      }
      final separatorIndex = segment.indexOf('=');
      final name = segment.substring(0, separatorIndex).trim();
      final value = segment.substring(separatorIndex + 1).trim();
      if (name.isEmpty || value.isEmpty) {
        continue;
      }
      output[name] = value;
    }
    return output;
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ForumWebViewState state,
    ForumWebViewDriver driver,
  ) {
    final title = _resolveTitle(state);

    return AppBar(
      automaticallyImplyLeading: false,
      leading: state.pageKind == ForumWebViewPageKind.home
          ? null
          : BackButton(
              key: const Key('forum-webview-back-button'),
              onPressed: () {
                unawaited(_handleBackPressed(driver, state));
              },
            ),
      title: Text(title),
      actions: [
        if (state.pageKind != ForumWebViewPageKind.search)
          IconButton(
            key: const Key('forum-webview-search-button'),
            tooltip: _searchTooltip(state),
            onPressed: () {
              unawaited(_loadSearchPage(driver, state));
            },
            icon: const Icon(Icons.search),
          ),
        PopupMenuButton<String>(
          key: const Key('forum-webview-more-button'),
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            unawaited(_handleMoreMenuSelected(context, state, driver, value));
          },
          itemBuilder: (context) => _buildMoreMenuItems(state),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMoreMenuItems(ForumWebViewState state) {
    switch (state.pageKind) {
      case ForumWebViewPageKind.home:
        return const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            key: Key('forum-webview-home-unfavorite-action'),
            value: _homeUnfavoriteAction,
            child: Text('取消收藏'),
          ),
        ];
      case ForumWebViewPageKind.forumDisplay:
        if (state.isFavoriteMutationLoading) {
          return const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              enabled: false,
              value: 'favorite-loading',
              child: Text('处理中'),
            ),
          ];
        }
        return <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            key: const Key('forum-webview-forum-favorite-action'),
            value: state.currentFavoriteForum == null
                ? _forumFavoriteAction
                : _forumUnfavoriteAction,
            child: Text(state.currentFavoriteForum == null ? '收藏本版' : '取消收藏'),
          ),
        ];
      case ForumWebViewPageKind.threadDetail:
        return const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            value: 'placeholder',
            child: Text('功能开发中'),
          ),
        ];
      case ForumWebViewPageKind.search:
        return const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            key: Key('forum-webview-search-home-action'),
            value: _searchGoHomeAction,
            child: Text('返回首页'),
          ),
        ];
      case ForumWebViewPageKind.other:
        return const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            value: 'placeholder',
            child: Text('功能开发中'),
          ),
        ];
    }
  }

  String _resolveTitle(ForumWebViewState state) {
    switch (state.pageKind) {
      case ForumWebViewPageKind.home:
        return '百合会论坛';
      case ForumWebViewPageKind.forumDisplay:
      case ForumWebViewPageKind.threadDetail:
        return state.boardName ?? '百合会论坛';
      case ForumWebViewPageKind.search:
        if (state.searchScope == ForumWebViewSearchScope.curForum) {
          if (state.boardName != null) {
            return '${state.boardName}搜索';
          }
          if (state.fid != null) {
            return 'fid=${state.fid}搜索';
          }
        }
        return '论坛搜索';
      case ForumWebViewPageKind.other:
        return state.pageTitle ?? '百合会论坛';
    }
  }

  String _searchTooltip(ForumWebViewState state) {
    if ((state.pageKind == ForumWebViewPageKind.forumDisplay ||
            state.pageKind == ForumWebViewPageKind.threadDetail) &&
        state.fid != null) {
      return '搜索本版';
    }
    return '搜索论坛';
  }

  Future<void> _loadSearchPage(
    ForumWebViewDriver driver,
    ForumWebViewState state,
  ) async {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final targetUri =
        ((state.pageKind == ForumWebViewPageKind.forumDisplay ||
                    state.pageKind == ForumWebViewPageKind.threadDetail) &&
                state.fid != null)
            ? navigator.curForumSearchUri(fid: state.fid!)
            : navigator.forumSearchUri();
    await driver.load(targetUri);
  }

  Future<void> _handleBackPressed(
    ForumWebViewDriver driver,
    ForumWebViewState state,
  ) async {
    if (state.canGoBack) {
      await driver.goBack();
      return;
    }
    final navigator = ref.read(forumWebViewNavigatorProvider);
    await driver.load(navigator.homeUri);
  }

  Future<String?> _readPageTitle(ForumWebViewDriver driver) async {
    try {
      return await driver.getTitle();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _readCanGoBack(ForumWebViewDriver driver) async {
    try {
      return await driver.canGoBack();
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleMoreMenuSelected(
    BuildContext context,
    ForumWebViewState state,
    ForumWebViewDriver driver,
    String action,
  ) async {
    switch (action) {
      case _homeUnfavoriteAction:
        await _openFavoriteForumPicker(context, driver);
        return;
      case _searchGoHomeAction:
        final navigator = ref.read(forumWebViewNavigatorProvider);
        await driver.load(navigator.homeUri);
        return;
      case _forumFavoriteAction:
        await _runForumFavoriteAction(
          context: context,
          driver: driver,
          reloadUri: state.currentUri,
          action: ref
              .read(forumWebViewControllerProvider.notifier)
              .favoriteCurrentForum,
        );
        return;
      case _forumUnfavoriteAction:
        await _runForumFavoriteAction(
          context: context,
          driver: driver,
          reloadUri: state.currentUri,
          action: ref
              .read(forumWebViewControllerProvider.notifier)
              .unfavoriteCurrentForum,
        );
        return;
    }
  }

  Future<void> _openFavoriteForumPicker(
    BuildContext context,
    ForumWebViewDriver driver,
  ) {
    final controller = ref.read(forumWebViewControllerProvider.notifier);
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final messenger = ScaffoldMessenger.of(context);
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final sheetNavigator = Navigator.of(sheetContext);
        return _FavoriteForumPickerSheet(
          loadFavoriteForums: controller.loadFavoriteForums,
          onUnfavorite: (forum) async {
            final result = await controller.unfavoriteForumByFavid(
              favid: forum.favid,
            );
            if (!mounted || !messenger.mounted) {
              return;
            }
            if (result case ApiSuccess<ForumFavoriteMutationResult>(:final data)) {
              if (sheetNavigator.mounted) {
                sheetNavigator.pop();
              }
              _showSnackBar(messenger, data.message);
              await driver.load(navigator.homeUri);
              return;
            }
            final message =
                result.errorOrNull?.message ?? '取消收藏失败，请稍后重试';
            _showSnackBar(messenger, message);
          },
        );
      },
    );
  }

  Future<void> _runForumFavoriteAction({
    required BuildContext context,
    required ForumWebViewDriver driver,
    required Uri reloadUri,
    required Future<ApiResult<ForumFavoriteMutationResult>> Function() action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action();
    if (!mounted || !messenger.mounted) {
      return;
    }
    if (result case ApiSuccess<ForumFavoriteMutationResult>(:final data)) {
      _showSnackBar(messenger, data.message);
      await driver.load(reloadUri);
      return;
    }
    final message = result.errorOrNull?.message ?? '操作失败，请稍后重试';
    _showSnackBar(messenger, message);
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String message) {
    if (!messenger.mounted) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }
}

class _FavoriteForumPickerSheet extends StatefulWidget {
  const _FavoriteForumPickerSheet({
    required this.loadFavoriteForums,
    required this.onUnfavorite,
  });

  final Future<ApiResult<List<FavoriteForum>>> Function() loadFavoriteForums;
  final Future<void> Function(FavoriteForum forum) onUnfavorite;

  @override
  State<_FavoriteForumPickerSheet> createState() => _FavoriteForumPickerSheetState();
}

class _FavoriteForumPickerSheetState extends State<_FavoriteForumPickerSheet> {
  late Future<ApiResult<List<FavoriteForum>>> _future;
  String? _submittingFavid;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFavoriteForums();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        key: const Key('forum-favorite-forum-picker'),
        height: 360,
        child: FutureBuilder<ApiResult<List<FavoriteForum>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final result = snapshot.data;
            if (result == null) {
              return _FavoriteForumPickerErrorView(
                message: '加载收藏版块失败',
                onRetry: _reload,
              );
            }

            return result.when(
              success: (forums) {
                if (forums.isEmpty) {
                  return const Center(
                    child: Text('暂无收藏版块'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('取消收藏'),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: forums.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final forum = forums[index];
                          final isSubmitting = _submittingFavid == forum.favid;
                          return ListTile(
                            key: Key('forum-favorite-forum-item-${forum.favid}'),
                            enabled: _submittingFavid == null,
                            title: Text(forum.title),
                            subtitle: Text('fid=${forum.fid}'),
                            trailing: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : null,
                            onTap: _submittingFavid == null
                                ? () => _handleUnfavorite(forum)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              failure: (error) => _FavoriteForumPickerErrorView(
                message: error.message,
                onRetry: _reload,
              ),
            );
          },
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _future = widget.loadFavoriteForums();
    });
  }

  Future<void> _handleUnfavorite(FavoriteForum forum) async {
    setState(() {
      _submittingFavid = forum.favid;
    });
    await widget.onUnfavorite(forum);
    if (!mounted) {
      return;
    }
    setState(() {
      _submittingFavid = null;
    });
  }
}

class _FavoriteForumPickerErrorView extends StatelessWidget {
  const _FavoriteForumPickerErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('forum-favorite-forum-picker-retry'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
