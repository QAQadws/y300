import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/data/services/forum_webview_redirect_resolver.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_cookie_bootstrapper.dart';
import 'package:y300/features/forum/domain/services/forum_webview_early_script_builder.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigation_header_builder.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_network_policy_resolver.dart';
import 'package:y300/features/forum/domain/services/forum_webview_post_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_reply_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_document_bridge.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_link_router.dart';
import 'package:y300/features/forum/domain/services/forum_webview_visual_policy_resolver.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/forum_text_resolver.dart';
import 'package:y300/features/forum/presentation/mappers/forum_webview_history_visit_mapper.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_history_coordinator.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_resource_diagnostic_recorder.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_page.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_text_resolver.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

class ForumWebViewPage extends ConsumerStatefulWidget {
  const ForumWebViewPage({super.key});

  @override
  ConsumerState<ForumWebViewPage> createState() => _ForumWebViewPageState();
}

class _ForumWebViewPageState extends ConsumerState<ForumWebViewPage> {
  static const String _refreshPageAction = 'refresh-page';
  static const String _homeUnfavoriteAction = 'home-unfavorite';
  static const String _forumFavoriteAction = 'forum-favorite';
  static const String _forumUnfavoriteAction = 'forum-unfavorite';
  static const String _searchGoHomeAction = 'search-go-home';
  static const String _threadAuthorOnlyAction = 'thread-author-only';
  static const String _threadNormalThreadAction = 'thread-normal-thread';
  static const String _threadReverseOrderAction = 'thread-reverse-order';
  static const String _threadNormalOrderAction = 'thread-normal-order';
  static const String _threadGoHomeAction = 'thread-go-home';
  static const List<ForumWebViewPageKind> _managedPageKinds =
      <ForumWebViewPageKind>[
        ForumWebViewPageKind.home,
        ForumWebViewPageKind.forumDisplay,
        ForumWebViewPageKind.threadDetail,
        ForumWebViewPageKind.search,
        ForumWebViewPageKind.other,
      ];

  bool _didScheduleInitialization = false;
  int _navigationGeneration = 0;
  Timer? _delayedCleanupTimer;
  ForumWebViewBootstrapConfig? _bootstrapConfig;
  late final ForumWebViewHistoryCoordinator _historyCoordinator;

  @override
  void initState() {
    super.initState();
    final historyDiagnostics = ref.read(historyDiagnosticRecorderProvider);
    _historyCoordinator = ForumWebViewHistoryCoordinator(
      onCommit: _recordHistoryVisit,
      onCommitFailure: (candidate, error, _) {
        debugPrint(
          '[ForumWebView][history_record_failure] '
          'error=${error.runtimeType}',
        );
      },
      onSkip: (reason) {
        historyDiagnostics.recordSkip(
          surface: HistoryVisitSurface.threadWebView,
          reason: 'webview_${reason.name}',
        );
      },
    );
  }

  @override
  void dispose() {
    _delayedCleanupTimer?.cancel();
    _historyCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigator = ref.watch(forumWebViewNavigatorProvider);
    final asyncState = ref.watch(forumWebViewControllerProvider);
    final initialUri = ref.watch(forumWebViewInitialUriProvider);
    final popOnRootBack = ref.watch(forumWebViewPopOnRootBackProvider);
    final hostPurpose = ref.watch(forumWebViewHostPurposeProvider);
    final overlayStyle = _resolveSystemUiOverlayStyle(context);
    final homeUri = initialUri ?? navigator.homeUri;
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
          threadDetailMenu: null,
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope<Object?>(
        canPop: _shouldAllowRoutePop(state, popOnRootBack: popOnRootBack),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }
          unawaited(
            _handleBackNavigation(driver, state, popOnRootBack: popOnRootBack),
          );
        },
        child: Scaffold(
          key: const Key('forum-webview-page'),
          appBar: _buildAppBar(
            context,
            state,
            driver,
            overlayStyle: overlayStyle,
            popOnRootBack: popOnRootBack,
            hostPurpose: hostPurpose,
          ),
          body: _buildWebViewSurface(context: context, driver: driver),
        ),
      ),
    );
  }

  Future<void> _initialize(ForumWebViewDriver driver) async {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final bootstrapper = ref.read(forumWebViewCookieBootstrapperProvider);
    final visualPolicyResolver = ref.read(
      forumWebViewVisualPolicyResolverProvider,
    );
    final earlyScriptBuilder = ref.read(forumWebViewEarlyScriptBuilderProvider);
    final networkPolicyResolver = ref.read(
      forumWebViewNetworkPolicyResolverProvider,
    );
    final capabilityProfile = await driver.probeCapabilities();
    if (!mounted) {
      return;
    }
    _historyCoordinator.configure(
      supportsPageCommitVisible: capabilityProfile.supportsPageCommitVisible,
    );

    final visualPolicy = visualPolicyResolver.resolve(
      ForumWebViewPageKind.home,
    );
    // Initial user scripts are registered once per WebView runtime, but they
    // run on every later managed-page navigation. Only merge early-safe
    // selectors here so late-only cleanup targets such as forum/search PWA
    // chrome stay out of document-start injection.
    final initialVisualPolicy = _mergeEarlyHiddenPolicies(
      _managedPageKinds.map(visualPolicyResolver.resolve),
    );
    final initialUserScripts = earlyScriptBuilder.build(
      capabilityProfile: capabilityProfile,
      visualPolicy: initialVisualPolicy,
    );
    final initialUri =
        ref.read(forumWebViewInitialUriProvider) ?? navigator.homeUri;
    final networkPolicy = networkPolicyResolver.resolve(initialUri);
    final bootstrapConfig = ForumWebViewBootstrapConfig(
      initialUri: initialUri,
      capabilityProfile: capabilityProfile,
      visualPolicy: visualPolicy,
      initialUserScripts: initialUserScripts,
      networkPolicy: networkPolicy,
    );

    await driver.initialize(
      callbacks: ForumWebViewCallbacks(
        onPageStarted: _handlePageStarted,
        onPageFinished: _handlePageFinished,
        onPageCommitVisible: _handlePageCommitVisible,
        onProgress: _handleProgress,
        onNavigationRequest: _handleNavigationRequest,
        onResourceDiagnostic: _handleResourceDiagnostic,
      ),
      bootstrapConfig: bootstrapConfig,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _bootstrapConfig = bootstrapConfig;
    });

    // API 登录/退出会通过 auth-scoped ProviderScope 重建整个 WebView 壳；
    // 每次重建都先清空平台 cookie jar，再从 CookieStore 单向 bootstrap 到 WebView。
    try {
      await driver.clearCookies();
    } catch (_) {
      // 清空失败时继续 seed，避免阻断论坛首页加载。
    }
    if (!mounted) {
      return;
    }

    final cookies = await bootstrapper.buildSeedCookies(uri: initialUri);
    if (!mounted) {
      return;
    }

    await driver.seedCookies(domain: initialUri.host, cookies: cookies);
    if (!mounted) {
      return;
    }

    await _loadManagedUri(driver, initialUri);
  }

  void _handlePageStarted(String url) {
    if (!mounted) {
      return;
    }
    _delayedCleanupTimer?.cancel();
    _delayedCleanupTimer = null;
    _navigationGeneration += 1;
    final uri = ref.read(forumWebViewNavigatorProvider).resolve(url);
    _historyCoordinator.onPageStarted(
      generation: _navigationGeneration,
      uri: uri,
    );
    ref.read(forumWebViewControllerProvider.notifier).onPageStarted(url);
  }

  void _handlePageCommitVisible(String url) {
    if (!mounted) {
      return;
    }
    final uri = ref.read(forumWebViewNavigatorProvider).resolve(url);
    unawaited(
      _historyCoordinator.onPageCommitVisible(
        generation: _navigationGeneration,
        uri: uri,
      ),
    );
  }

  Future<void> _handlePageFinished(String url) async {
    if (!mounted) {
      return;
    }
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final injector = ref.read(forumWebViewScriptInjectorProvider);
    final threadDocumentBridge = ref.read(
      forumWebViewThreadDocumentBridgeProvider,
    );
    final visualPolicyResolver = ref.read(
      forumWebViewVisualPolicyResolverProvider,
    );
    final driver = ref.read(forumWebViewDriverProvider);
    final uri = navigator.resolve(url);
    final pageKind = navigator.classify(uri);
    if (_isPostEditTargetRedirect(uri)) {
      _completePostEditWebView(ForumWebViewRouteOutcome.observedTargetRedirect);
      return;
    }
    final visualPolicy = visualPolicyResolver.resolve(pageKind);
    final generation = _navigationGeneration;

    final pageTitle = await _readPageTitle(driver);
    final canGoBack = await _readCanGoBack(driver);
    if (!mounted || generation != _navigationGeneration) {
      return;
    }
    final threadDocumentSnapshot = pageKind == ForumWebViewPageKind.threadDetail
        ? await _readThreadDocumentSnapshot(
            driver: driver,
            navigator: navigator,
            threadDocumentBridge: threadDocumentBridge,
          )
        : null;
    if (!mounted || generation != _navigationGeneration) {
      return;
    }
    await ref
        .read(forumWebViewControllerProvider.notifier)
        .onPageFinished(
          rawUrl: url,
          pageTitle: pageTitle,
          canGoBack: canGoBack,
          threadMenuSnapshot: threadDocumentSnapshot?.menu,
        );
    if (!mounted || generation != _navigationGeneration) {
      return;
    }
    final completedState = ref
        .read(forumWebViewControllerProvider)
        .asData
        ?.value;
    final forumName =
        threadDocumentSnapshot?.forumName ??
        (completedState?.fid == null ? null : completedState?.boardName);
    unawaited(
      _historyCoordinator.onPageFinished(
        generation: generation,
        finalUri: uri,
        document: threadDocumentSnapshot,
        forumName: forumName,
      ),
    );
    if (!navigator.isManagedSite(uri)) {
      return;
    }

    // 逛论坛时持续把 WebView 赢得的 cookie（刷新过的 WAF 通行证 / 登录态）
    // 回灌 dio，让原生 API 功能（收藏、回复、搜索）始终握着有效凭证。
    // best-effort：同步失败不影响页面清理主流程。
    unawaited(_syncWebViewCookiesToDio(uri));

    await injector.cleanChrome(driver, visualPolicy: visualPolicy);

    _delayedCleanupTimer?.cancel();
    _delayedCleanupTimer = Timer(const Duration(milliseconds: 300), () async {
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
      await injector.cleanChrome(driver, visualPolicy: visualPolicy);
    });
  }

  /// 把当前 WebView 作用域下的 cookie 回灌 dio（WebView → dio 单向同步）。
  Future<void> _syncWebViewCookiesToDio(Uri uri) async {
    try {
      await ref.read(webViewCookieSyncServiceProvider).syncToStore(uri);
    } catch (_) {
      // 同步失败不影响浏览体验，下次 pageFinished 会再次尝试。
    }
  }

  void _handleProgress(int progress) {
    if (!mounted) {
      return;
    }
    ref.read(forumWebViewControllerProvider.notifier).onProgress(progress);
  }

  void _handleResourceDiagnostic(ForumWebViewResourceDiagnosticEvent event) {
    ref.read(forumWebViewResourceDiagnosticRecorderProvider).record(event);
  }

  FutureOr<ForumWebViewNavigationDecision> _handleNavigationRequest(
    String url,
  ) {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final uri = navigator.resolve(url);
    if (uri.scheme.toLowerCase() == 'javascript') {
      return ForumWebViewNavigationDecision.prevent;
    }
    if (_isPostEditTargetRedirect(uri)) {
      _completePostEditWebView(ForumWebViewRouteOutcome.observedTargetRedirect);
      return ForumWebViewNavigationDecision.prevent;
    }
    final postReplyRequest = ref
        .read(forumWebViewReplyNavigatorProvider)
        .resolvePostReply(url);
    if (postReplyRequest != null) {
      unawaited(_openPostReplyComposer(context, postReplyRequest));
      return ForumWebViewNavigationDecision.prevent;
    }
    final newThreadRequest = ref
        .read(forumWebViewPostNavigatorProvider)
        .resolveNewThread(url);
    if (newThreadRequest != null) {
      unawaited(_openPostingComposer(context, newThreadRequest));
      return ForumWebViewNavigationDecision.prevent;
    }
    if (_isPostComposerUrl(uri)) {
      return navigator.isManagedSite(uri)
          ? ForumWebViewNavigationDecision.navigate
          : ForumWebViewNavigationDecision.prevent;
    }
    if (navigator.isManagedSite(uri)) {
      final resolution = ref
          .read(forumWebViewThreadLinkRouterProvider)
          .resolve(url);
      if (resolution.isThreadLink) {
        unawaited(_openThreadLink(resolution));
        return ForumWebViewNavigationDecision.prevent;
      }
      if (resolution.normalizedUri != resolution.originalUri) {
        final driver = ref.read(forumWebViewDriverProvider);
        unawaited(
          _loadManagedUri(
            driver,
            resolution.normalizedUri,
            referrerUri: ref
                .read(forumWebViewControllerProvider)
                .asData
                ?.value
                .currentUri,
          ),
        );
        return ForumWebViewNavigationDecision.prevent;
      }
      return ForumWebViewNavigationDecision.navigate;
    }

    unawaited(_launchExternalUri(uri));
    return ForumWebViewNavigationDecision.prevent;
  }

  Future<void> _openThreadLink(
    ForumWebViewThreadLinkResolution resolution,
  ) async {
    final mode = await ref.read(forumShellModeControllerProvider.future);
    if (!mounted) {
      return;
    }
    if (mode == ForumShellMode.webview) {
      await _openThreadLinkInWebView(resolution);
      return;
    }
    await _openThreadLinkNatively(resolution);
  }

  Future<void> _openThreadLinkInWebView(
    ForumWebViewThreadLinkResolution resolution,
  ) {
    return _loadManagedUri(
      ref.read(forumWebViewDriverProvider),
      resolution.normalizedUri,
      referrerUri: ref
          .read(forumWebViewControllerProvider)
          .asData
          ?.value
          .currentUri,
    );
  }

  Future<void> _openThreadLinkNatively(
    ForumWebViewThreadLinkResolution resolution,
  ) async {
    switch (resolution.kind) {
      case ForumWebViewThreadLinkKind.thread:
        _pushNativeThread(tid: resolution.tid!);
        return;
      case ForumWebViewThreadLinkKind.threadPost:
        _pushNativeThread(
          tid: resolution.tid!,
          initialPage: resolution.page,
          targetPid: resolution.pid,
        );
        return;
      case ForumWebViewThreadLinkKind.findPostRedirect:
        await _openNativeFindPostRedirect(resolution);
        return;
      case ForumWebViewThreadLinkKind.emptyFindPostRedirect:
        await _openNativeEmptyFindPostRedirect(resolution);
        return;
      case ForumWebViewThreadLinkKind.none:
        await _openThreadLinkInWebView(resolution);
        return;
    }
  }

  Future<void> _openNativeFindPostRedirect(
    ForumWebViewThreadLinkResolution resolution,
  ) async {
    final result = await ref
        .read(threadPostLocatorProvider)
        .locate(
          tid: resolution.tid!,
          pid: resolution.pid!,
          sourceUri: resolution.normalizedUri,
        );
    if (!mounted) {
      return;
    }
    if (result case ApiSuccess<ThreadPostLocation>(:final data)) {
      _pushNativeThread(
        tid: data.tid,
        initialPage: data.page,
        targetPid: data.pid,
      );
      return;
    }
    _showSnackBar(
      ScaffoldMessenger.of(context),
      AppLocalizations.of(context).forumWebViewLocationFallback,
    );
    _pushNativeThread(tid: resolution.tid!);
  }

  Future<void> _openNativeEmptyFindPostRedirect(
    ForumWebViewThreadLinkResolution resolution,
  ) async {
    final result = await ref
        .read(forumWebViewRedirectResolverProvider)
        .resolve(resolution.normalizedUri);
    if (!mounted) {
      return;
    }
    if (result case ApiSuccess<ForumWebViewRedirectResolution>(:final data)) {
      final finalResolution = ref
          .read(forumWebViewThreadLinkRouterProvider)
          .resolve(data.finalUri.toString());
      if (finalResolution.kind == ForumWebViewThreadLinkKind.thread ||
          finalResolution.kind == ForumWebViewThreadLinkKind.threadPost) {
        await _openThreadLinkNatively(finalResolution);
        return;
      }
    }
    final messenger = ScaffoldMessenger.of(context);
    _showSnackBar(
      messenger,
      AppLocalizations.of(context).forumWebViewPostLinkFallback,
    );
    await _openThreadLinkInWebView(resolution);
  }

  void _pushNativeThread({
    required String tid,
    int? initialPage,
    String? targetPid,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: tid,
          initialPage: initialPage,
          targetPid: targetPid,
        ),
      ),
    );
  }

  bool _isPostComposerUrl(Uri uri) {
    if (!ref.read(forumWebViewNavigatorProvider).isManagedSite(uri) ||
        !uri.path.endsWith('/forum.php')) {
      return false;
    }
    final query = uri.queryParameters;
    return query['mod'] == 'post' &&
        (query['action'] == 'reply' || query['action'] == 'newthread');
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ForumWebViewState state,
    ForumWebViewDriver driver, {
    required SystemUiOverlayStyle overlayStyle,
    required bool popOnRootBack,
    required ForumWebViewHostPurpose hostPurpose,
  }) {
    final l10n = AppLocalizations.of(context);
    final title = ForumTextResolver.webViewTitle(l10n, state);

    return AppBar(
      automaticallyImplyLeading: false,
      systemOverlayStyle: overlayStyle,
      leading: state.pageKind == ForumWebViewPageKind.home
          ? null
          : BackButton(
              key: const Key('forum-webview-back-button'),
              onPressed: () {
                unawaited(
                  _handleBackNavigation(
                    driver,
                    state,
                    popOnRootBack: popOnRootBack,
                  ),
                );
              },
            ),
      title: Text(title),
      actions: [
        if (hostPurpose == ForumWebViewHostPurpose.postEditFallback)
          IconButton(
            key: const Key('forum-webview-post-edit-native-button'),
            tooltip: l10n.postEditSwitchToNative,
            onPressed: () =>
                _completePostEditWebView(ForumWebViewRouteOutcome.returned),
            icon: const Icon(Icons.swap_horiz),
          ),
        if (_canShowSearchButton(state))
          IconButton(
            key: const Key('forum-webview-search-button'),
            tooltip: ForumTextResolver.searchTooltip(l10n, state),
            onPressed: () {
              unawaited(_loadSearchPage(driver, state));
            },
            icon: const Icon(Icons.search),
          ),
        if (_canOpenThreadReply(state))
          IconButton(
            key: const Key('forum-webview-thread-reply-button'),
            tooltip: l10n.forumWebViewReplyThread,
            onPressed: () {
              unawaited(_openThreadReplyComposer(context, state, driver));
            },
            icon: const Icon(Icons.reply),
          ),
        PopupMenuButton<String>(
          key: const Key('forum-webview-more-button'),
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            unawaited(_handleMoreMenuSelected(context, state, driver, value));
          },
          itemBuilder: (context) => _buildMoreMenuItems(context, state),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMoreMenuItems(
    BuildContext context,
    ForumWebViewState state,
  ) {
    final l10n = AppLocalizations.of(context);
    final refreshItem = PopupMenuItem<String>(
      key: Key('forum-webview-refresh-action'),
      value: _refreshPageAction,
      child: Text(l10n.forumWebViewRefresh),
    );

    switch (state.pageKind) {
      case ForumWebViewPageKind.home:
        return <PopupMenuEntry<String>>[
          refreshItem,
          PopupMenuItem<String>(
            key: Key('forum-webview-home-unfavorite-action'),
            value: _homeUnfavoriteAction,
            child: Text(l10n.forumWebViewCancelFavorite),
          ),
        ];
      case ForumWebViewPageKind.forumDisplay:
        return <PopupMenuEntry<String>>[
          refreshItem,
          ..._buildForumDisplayMoreMenuItems(context, state),
        ];
      case ForumWebViewPageKind.threadDetail:
        return <PopupMenuEntry<String>>[
          refreshItem,
          ..._buildThreadDetailMoreMenuItems(context, state),
        ];
      case ForumWebViewPageKind.search:
        return <PopupMenuEntry<String>>[
          refreshItem,
          PopupMenuItem<String>(
            key: Key('forum-webview-search-home-action'),
            value: _searchGoHomeAction,
            child: Text(l10n.forumWebViewBackHome),
          ),
        ];
      case ForumWebViewPageKind.other:
        return <PopupMenuEntry<String>>[refreshItem];
    }
  }

  List<PopupMenuEntry<String>> _buildForumDisplayMoreMenuItems(
    BuildContext context,
    ForumWebViewState state,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state.isFavoriteMutationLoading) {
      return <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          value: 'favorite-loading',
          child: Text(l10n.forumWebViewProcessing),
        ),
      ];
    }
    return <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        key: const Key('forum-webview-forum-favorite-action'),
        value: state.currentFavoriteForum == null
            ? _forumFavoriteAction
            : _forumUnfavoriteAction,
        child: Text(
          state.currentFavoriteForum == null
              ? l10n.forumWebViewFavoriteForum
              : l10n.forumWebViewUnfavoriteForum,
        ),
      ),
    ];
  }

  List<PopupMenuEntry<String>> _buildThreadDetailMoreMenuItems(
    BuildContext context,
    ForumWebViewState state,
  ) {
    final l10n = AppLocalizations.of(context);
    final menu =
        state.threadDetailMenu ?? _buildFallbackThreadDetailMenu(state);

    final items = <PopupMenuEntry<String>>[];
    if (!menu.isAuthorOnly && menu.authorOnlyUri != null) {
      items.add(
        PopupMenuItem<String>(
          key: Key('forum-webview-thread-author-action'),
          value: _threadAuthorOnlyAction,
          child: Text(l10n.forumWebViewAuthorOnly),
        ),
      );
    } else if (menu.isAuthorOnly && menu.normalThreadUri != null) {
      items.add(
        PopupMenuItem<String>(
          key: Key('forum-webview-thread-author-action'),
          value: _threadNormalThreadAction,
          child: Text(l10n.forumWebViewAllPosts),
        ),
      );
    }

    items.add(
      PopupMenuItem<String>(
        key: const Key('forum-webview-thread-order-action'),
        value: menu.isReverseOrder
            ? _threadNormalOrderAction
            : _threadReverseOrderAction,
        child: Text(
          menu.isReverseOrder
              ? l10n.forumWebViewNormalOrder
              : l10n.forumWebViewReverseOrder,
        ),
      ),
    );
    items.add(
      PopupMenuItem<String>(
        key: Key('forum-webview-thread-home-action'),
        value: _threadGoHomeAction,
        child: Text(l10n.forumWebViewBackHome),
      ),
    );
    return items;
  }

  ForumThreadDetailMenuState _buildFallbackThreadDetailMenu(
    ForumWebViewState state,
  ) {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    return ForumThreadDetailMenuState(
      isAuthorOnly: navigator.extractAuthorId(state.currentUri) != null,
      isReverseOrder: navigator.isReverseOrder(state.currentUri),
      authorOnlyUri: null,
      normalThreadUri: navigator.extractAuthorId(state.currentUri) != null
          ? navigator.buildNormalThreadUri(state.currentUri)
          : null,
      reverseOrderUri: navigator.buildReverseOrderUri(state.currentUri),
      normalOrderUri: navigator.buildNormalOrderUri(state.currentUri),
    );
  }

  bool _canShowSearchButton(ForumWebViewState state) {
    if (state.pageKind == ForumWebViewPageKind.search ||
        state.pageKind == ForumWebViewPageKind.threadDetail) {
      return false;
    }
    if (state.pageKind == ForumWebViewPageKind.forumDisplay) {
      return (state.fid ?? '').trim().isNotEmpty;
    }
    return true;
  }

  bool _canOpenThreadReply(ForumWebViewState state) {
    return state.pageKind == ForumWebViewPageKind.threadDetail &&
        (state.fid ?? '').trim().isNotEmpty &&
        (state.tid ?? '').trim().isNotEmpty;
  }

  Future<void> _openThreadReplyComposer(
    BuildContext context,
    ForumWebViewState state,
    ForumWebViewDriver driver,
  ) async {
    final fid = state.fid?.trim();
    final tid = state.tid?.trim();
    if (fid == null || fid.isEmpty || tid == null || tid.isEmpty) {
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final result = await navigator.push<ReplyComposerResult>(
      MaterialPageRoute<ReplyComposerResult>(
        builder: (_) => ReplyComposerPage(
          args: ReplyComposerArgs(
            target: ReplyTarget.thread(
              fid: fid,
              tid: tid,
              sourceUri: state.currentUri,
            ),
            title: state.pageTitle,
          ),
        ),
      ),
    );
    if (!mounted || result == null || !result.sent) {
      return;
    }
    if (messenger != null) {
      _showSnackBar(
        messenger,
        ComposerTextResolver.submitSuccess(
          l10n,
          ComposerKind.reply,
          result.rawSuccessDetail,
        ),
      );
    }
    await driver.reload();
  }

  Future<void> _openPostReplyComposer(
    BuildContext context,
    ForumWebViewPostReplyRequest request,
  ) async {
    if (!mounted) {
      return;
    }
    final driver = ref.read(forumWebViewDriverProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final result = await navigator.push<ReplyComposerResult>(
      MaterialPageRoute<ReplyComposerResult>(
        builder: (_) => ReplyComposerPage(
          args: ReplyComposerArgs(
            target: ReplyTarget.post(
              fid: request.fid,
              tid: request.tid,
              pid: request.repquote,
              sourceUri: request.replyFormUri,
            ),
            replyFormUri: request.replyFormUri,
          ),
        ),
      ),
    );
    if (!mounted || result == null || !result.sent) {
      return;
    }
    if (messenger != null) {
      _showSnackBar(
        messenger,
        ComposerTextResolver.submitSuccess(
          l10n,
          ComposerKind.reply,
          result.rawSuccessDetail,
        ),
      );
    }
    await driver.reload();
  }

  Future<void> _openPostingComposer(
    BuildContext context,
    ForumWebViewPostRequest request,
  ) async {
    if (!mounted) {
      return;
    }
    final driver = ref.read(forumWebViewDriverProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final result = await navigator.push<PostingComposerResult>(
      MaterialPageRoute<PostingComposerResult>(
        builder: (_) => PostingComposerPage(
          args: PostingComposerArgs(
            target: PostingTarget(
              fid: request.fid,
              sourceUri: request.sourceUri,
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == null || !result.sent) {
      return;
    }
    if (messenger != null) {
      _showSnackBar(
        messenger,
        ComposerTextResolver.submitSuccess(
          l10n,
          ComposerKind.newThread,
          result.rawSuccessDetail,
        ),
      );
    }
    // 方案 §4.2 本期保持简单：仅刷新当前 WebView。新帖 tid 已经在
    // PostingComposerResult.tid 里，可以在 Phase 7 改成 navigate 到该 tid。
    await driver.reload();
  }

  Future<void> _loadSearchPage(
    ForumWebViewDriver driver,
    ForumWebViewState state,
  ) async {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    final fid = state.fid?.trim();
    final targetUri =
        (state.pageKind == ForumWebViewPageKind.forumDisplay &&
            fid != null &&
            fid.isNotEmpty)
        ? navigator.curForumSearchUri(fid: fid)
        : navigator.forumSearchUri();
    await _loadManagedUri(driver, targetUri, referrerUri: state.currentUri);
  }

  Future<void> _handleBackNavigation(
    ForumWebViewDriver driver,
    ForumWebViewState state, {
    required bool popOnRootBack,
  }) async {
    if (state.canGoBack) {
      await driver.goBack();
      return;
    }
    if (popOnRootBack) {
      if (ref.read(forumWebViewHostPurposeProvider) ==
          ForumWebViewHostPurpose.postEditFallback) {
        _completePostEditWebView(ForumWebViewRouteOutcome.returned);
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (state.pageKind == ForumWebViewPageKind.home) {
      return;
    }
    final navigator = ref.read(forumWebViewNavigatorProvider);
    await _loadManagedUri(
      driver,
      navigator.homeUri,
      referrerUri: state.currentUri,
    );
  }

  bool _isPostEditTargetRedirect(Uri uri) {
    final target = ref.read(forumWebViewCompletionTargetProvider);
    if (ref.read(forumWebViewHostPurposeProvider) !=
            ForumWebViewHostPurpose.postEditFallback ||
        target == null ||
        !ref.read(forumWebViewNavigatorProvider).isManagedSite(uri) ||
        !uri.path.endsWith('/forum.php')) {
      return false;
    }
    final query = uri.queryParameters;
    final fragment = uri.fragment.trim();
    final queryPid = query['pid']?.trim();
    final isViewThreadTarget =
        query['mod'] == 'viewthread' &&
        query['tid'] == target.tid &&
        (fragment == 'pid${target.pid}' || queryPid == target.pid);
    final isFindPostRedirect =
        query['mod'] == 'redirect' &&
        query['goto'] == 'findpost' &&
        query['ptid'] == target.tid &&
        queryPid == target.pid;
    return isViewThreadTarget || isFindPostRedirect;
  }

  void _completePostEditWebView(ForumWebViewRouteOutcome outcome) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      ForumWebViewRouteResult(outcome: outcome, serverMutationPossible: true),
    );
  }

  bool _shouldAllowRoutePop(
    ForumWebViewState state, {
    required bool popOnRootBack,
  }) {
    if (popOnRootBack && !state.canGoBack) {
      return true;
    }
    return !state.canGoBack && state.pageKind == ForumWebViewPageKind.home;
  }

  Widget _buildWebViewSurface({
    required BuildContext context,
    required ForumWebViewDriver driver,
  }) {
    if (_bootstrapConfig == null) {
      return ColoredBox(
        key: const Key('forum-webview-bootstrap-placeholder'),
        color: Theme.of(context).colorScheme.surface,
      );
    }
    // Platform views must own vertical drag gestures directly. Re-wrapping the
    // WebView in a Flutter Scrollable brings back the mixed-shell scrolling
    // regressions UX-2 is trying to remove.
    return driver.buildWidget(key: const Key('forum-webview-surface'));
  }

  SystemUiOverlayStyle _resolveSystemUiOverlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(
          statusBarColor: Colors.transparent,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        );
  }

  Future<void> _launchExternalUri(Uri uri) async {
    if (!mounted) {
      return;
    }
    final launcher = ref.read(forumWebViewExternalLauncherProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final launched = await launcher.launch(uri);
    if (!mounted || launched) {
      return;
    }
    if (messenger != null) {
      _showSnackBar(
        messenger,
        AppLocalizations.of(context).forumWebViewOpenExternalFailed,
      );
    }
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

  Future<ForumThreadDocumentSnapshot?> _readThreadDocumentSnapshot({
    required ForumWebViewDriver driver,
    required ForumWebViewNavigator navigator,
    required ForumWebViewThreadDocumentBridge threadDocumentBridge,
  }) async {
    try {
      return await threadDocumentBridge.read(
        target: driver,
        navigator: navigator,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordHistoryVisit(
    ForumWebViewHistoryCandidate candidate,
  ) async {
    final draft = const ForumWebViewHistoryVisitMapper().map(candidate);
    await ref.read(historyVisitRecorderProvider).record(draft);
  }

  Future<void> _handleMoreMenuSelected(
    BuildContext context,
    ForumWebViewState state,
    ForumWebViewDriver driver,
    String action,
  ) async {
    switch (action) {
      case _refreshPageAction:
        await driver.reload();
        return;
      case _homeUnfavoriteAction:
        await _openFavoriteForumPicker(context, driver);
        return;
      case _searchGoHomeAction:
      case _threadGoHomeAction:
        final navigator = ref.read(forumWebViewNavigatorProvider);
        await _loadManagedUri(
          driver,
          navigator.homeUri,
          referrerUri: state.currentUri,
        );
        return;
      case _forumFavoriteAction:
        await _runForumFavoriteAction(
          context: context,
          driver: driver,
          reloadUri: state.currentUri,
          successMessage: AppLocalizations.of(
            context,
          ).forumWebViewFavoriteSuccess,
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
          successMessage: AppLocalizations.of(
            context,
          ).forumWebViewUnfavoriteSuccess,
          action: ref
              .read(forumWebViewControllerProvider.notifier)
              .unfavoriteCurrentForum,
        );
        return;
      case _threadAuthorOnlyAction:
        final authorOnlyUri = state.threadDetailMenu?.authorOnlyUri;
        if (authorOnlyUri != null) {
          await _loadManagedUri(
            driver,
            authorOnlyUri,
            referrerUri: state.currentUri,
          );
        }
        return;
      case _threadNormalThreadAction:
        final normalThreadUri = state.threadDetailMenu?.normalThreadUri;
        if (normalThreadUri != null) {
          await _loadManagedUri(
            driver,
            normalThreadUri,
            referrerUri: state.currentUri,
          );
        }
        return;
      case _threadReverseOrderAction:
        final reverseOrderUri = state.threadDetailMenu?.reverseOrderUri;
        if (reverseOrderUri != null) {
          await _loadManagedUri(
            driver,
            reverseOrderUri,
            referrerUri: state.currentUri,
          );
        }
        return;
      case _threadNormalOrderAction:
        final normalOrderUri = state.threadDetailMenu?.normalOrderUri;
        if (normalOrderUri != null) {
          await _loadManagedUri(
            driver,
            normalOrderUri,
            referrerUri: state.currentUri,
          );
        }
        return;
    }
  }

  Future<void> _openFavoriteForumPicker(
    BuildContext context,
    ForumWebViewDriver driver,
  ) {
    final l10n = AppLocalizations.of(context);
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
            if (result case ApiSuccess<ForumFavoriteMutationResult>()) {
              if (sheetNavigator.mounted) {
                sheetNavigator.pop();
              }
              _showSnackBar(messenger, l10n.forumWebViewUnfavoriteSuccess);
              final referrerUri =
                  ref
                      .read(forumWebViewControllerProvider)
                      .asData
                      ?.value
                      .currentUri ??
                  navigator.homeUri;
              await _loadManagedUri(
                driver,
                navigator.homeUri,
                referrerUri: referrerUri,
              );
              return;
            }
            _showSnackBar(
              messenger,
              ForumTextResolver.webViewActionFailure(
                l10n,
                result.errorOrNull?.message,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _runForumFavoriteAction({
    required BuildContext context,
    required ForumWebViewDriver driver,
    required Uri reloadUri,
    required String successMessage,
    required Future<ApiResult<ForumFavoriteMutationResult>> Function() action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await action();
    if (!mounted || !messenger.mounted) {
      return;
    }
    if (result case ApiSuccess<ForumFavoriteMutationResult>()) {
      _showSnackBar(messenger, successMessage);
      await _loadManagedUri(driver, reloadUri, referrerUri: reloadUri);
      return;
    }
    _showSnackBar(
      messenger,
      ForumTextResolver.webViewActionFailure(l10n, result.errorOrNull?.message),
    );
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String message) {
    if (!messenger.mounted) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadManagedUri(
    ForumWebViewDriver driver,
    Uri targetUri, {
    Uri? referrerUri,
  }) {
    final navigator = ref.read(forumWebViewNavigatorProvider);
    if (!navigator.isManagedSite(targetUri)) {
      return driver.load(targetUri);
    }
    final headers = _buildManagedNavigationHeaders(
      targetUri: targetUri,
      referrerUri: referrerUri,
    );
    return driver.load(targetUri, headers: headers);
  }

  Map<String, String> _buildManagedNavigationHeaders({
    required Uri targetUri,
    Uri? referrerUri,
  }) {
    final headerBuilder = ref.read(forumWebViewNavigationHeaderBuilderProvider);
    final policy = _resolveNetworkPolicy(targetUri);
    return headerBuilder.build(
      targetUri: targetUri,
      referrerUri: referrerUri,
      policy: policy,
    );
  }

  ForumWebViewNetworkPolicy _resolveNetworkPolicy(Uri targetUri) {
    final bootstrapConfig = _bootstrapConfig;
    if (bootstrapConfig != null && bootstrapConfig.initialUri == targetUri) {
      return bootstrapConfig.networkPolicy;
    }
    return ref
        .read(forumWebViewNetworkPolicyResolverProvider)
        .resolve(targetUri);
  }

  ForumWebViewVisualPolicy _mergeEarlyHiddenPolicies(
    Iterable<ForumWebViewVisualPolicy> policies,
  ) {
    final collectedPolicies = policies.toList(growable: false);
    return ForumWebViewVisualPolicy(
      earlyHiddenSelectors: Set<String>.unmodifiable(
        collectedPolicies.expand((policy) => policy.earlyHiddenSelectors),
      ),
      lateRemovedSelectors: const <String>{},
      extraCss: _mergeCssBlocks(
        collectedPolicies.map((policy) => policy.extraCss),
      ),
      disableHorizontalOverflow: collectedPolicies.any(
        (policy) => policy.disableHorizontalOverflow,
      ),
    );
  }

  String _mergeCssBlocks(Iterable<String> blocks) {
    final mergedBlocks = <String>{};
    for (final block in blocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) {
        continue;
      }
      mergedBlocks.add(trimmedBlock);
    }
    return mergedBlocks.join('\n');
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
  State<_FavoriteForumPickerSheet> createState() =>
      _FavoriteForumPickerSheetState();
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
                message: ForumTextResolver.favoriteForumsLoadFailure(
                  AppLocalizations.of(context),
                  null,
                ),
                onRetry: _reload,
              );
            }

            return result.when(
              success: (forums) {
                if (forums.isEmpty) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context).forumWebViewNoFavoriteForums,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        AppLocalizations.of(
                          context,
                        ).forumWebViewFavoriteForumsTitle,
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: forums.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final forum = forums[index];
                          final isSubmitting = _submittingFavid == forum.favid;
                          return ListTile(
                            key: Key(
                              'forum-favorite-forum-item-${forum.favid}',
                            ),
                            enabled: _submittingFavid == null,
                            title: Text(forum.title),
                            subtitle: Text(
                              AppLocalizations.of(
                                context,
                              ).forumWebViewForumByFid(forum.fid),
                            ),
                            trailing: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                message: ForumTextResolver.favoriteForumsLoadFailure(
                  AppLocalizations.of(context),
                  error.message,
                ),
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
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
