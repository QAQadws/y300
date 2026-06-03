import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';

class ForumWebViewPage extends ConsumerStatefulWidget {
  const ForumWebViewPage({super.key});

  @override
  ConsumerState<ForumWebViewPage> createState() => _ForumWebViewPageState();
}

class _ForumWebViewPageState extends ConsumerState<ForumWebViewPage> {
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
          fid: null,
          tid: null,
          boardName: null,
          pageTitle: null,
          canGoBack: false,
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
        IconButton(
          key: const Key('forum-webview-search-button'),
          tooltip: _searchTooltip(state),
          onPressed: () => _openSearch(context, state),
          icon: const Icon(Icons.search),
        ),
        PopupMenuButton<String>(
          key: const Key('forum-webview-more-button'),
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) {
            return const [
              PopupMenuItem<String>(
                enabled: false,
                value: 'placeholder',
                child: Text('功能开发中'),
              ),
            ];
          },
        ),
      ],
    );
  }

  String _resolveTitle(ForumWebViewState state) {
    switch (state.pageKind) {
      case ForumWebViewPageKind.home:
        return '百合会论坛';
      case ForumWebViewPageKind.forumDisplay:
      case ForumWebViewPageKind.threadDetail:
        return state.boardName ?? '百合会论坛';
      case ForumWebViewPageKind.search:
        return state.boardName ?? '搜索';
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

  void _openSearch(BuildContext context, ForumWebViewState state) {
    final searchContext =
        ((state.pageKind == ForumWebViewPageKind.forumDisplay ||
                    state.pageKind == ForumWebViewPageKind.threadDetail) &&
                state.fid != null)
            ? DiscuzSearchContext.curForum(srhfid: state.fid!)
            : const DiscuzSearchContext.forum();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForumSearchPage(context: searchContext),
      ),
    );
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
}
