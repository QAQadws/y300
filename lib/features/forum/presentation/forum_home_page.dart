import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/data/services/forum_home_request_profile_resolver.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';
import 'package:y300/features/forum/presentation/forum_content_projection_providers.dart';
import 'package:y300/features/forum/presentation/forum_home_content_projection.dart';
import 'package:y300/features/forum/presentation/forum_home_content_projector.dart';
import 'package:y300/features/forum/presentation/forum_home_controller.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/forum/presentation/forum_text_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/widgets/forum_home_widgets.dart';
import 'package:y300/features/forum/presentation/widgets/forum_favorite_forum_picker.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/app_popup_menu.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';

const Duration _forumHomeSilentRefreshThreshold = Duration(seconds: 60);

class ForumHomePage extends ConsumerStatefulWidget {
  const ForumHomePage({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<ForumHomePage> createState() => _ForumHomePageState();
}

class _ForumHomePageState extends ConsumerState<ForumHomePage>
    with WidgetsBindingObserver {
  static const String _refreshPageAction = 'refresh-page';
  static const String _unfavoriteAction = 'unfavorite';
  ProviderSubscription<AsyncValue<AuthSessionViewState>>? _authSubscription;
  String? _lastResolvedAuthContextKey;
  bool _isHandlingAuthContextChange = false;
  bool _isSwitchingAuthContext = false;
  int _authContextGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = ref.listenManual<AsyncValue<AuthSessionViewState>>(
      authSessionControllerProvider,
      (previous, next) {
        final nextState = next.asData?.value;
        if (nextState == null) {
          return;
        }
        unawaited(_reconcileAuthContext(nextState));
      },
      fireImmediately: true,
    );
  }

  @override
  void didUpdateWidget(covariant ForumHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_triggerSilentRefreshIfNeeded());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      unawaited(_triggerSilentRefreshIfNeeded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.close();
    _authSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.forumHomeTitle),
        actions: [
          IconButton(
            key: const Key('forum-home-search-button'),
            tooltip: l10n.forumHomeSearch,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ForumSearchPage(),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
          AppPopupMenuButton<String>(
            key: const Key('forum-home-more-button'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              unawaited(_handleMoreMenuSelected(context, value));
            },
            itemBuilder: (context) => [
              AppPopupMenuItem<String>(
                key: const Key('forum-home-refresh-action'),
                value: _refreshPageAction,
                label: l10n.forumRefreshPage,
              ),
              AppPopupMenuItem<String>(
                key: const Key('forum-home-unfavorite-action'),
                value: _unfavoriteAction,
                label: l10n.forumUnfavoriteForum,
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: _isSwitchingAuthContext,
            child: _ResolvedForumHomeBody(
              imageHeaderBuilder: imageHeaderBuilder,
              isActive: widget.isActive,
            ),
          ),
          if (_isSwitchingAuthContext) const _ForumHomeBlankBody(),
        ],
      ),
    );
  }

  Future<void> _reconcileAuthContext(AuthSessionViewState authState) async {
    final generation = ++_authContextGeneration;
    final localProfile = await ref
        .read(forumHomeRequestProfileResolverProvider)
        .resolve();
    if (!mounted || generation != _authContextGeneration) {
      return;
    }

    final effectiveProfile = authState.isLoggedIn
        ? DocumentRequestProfile.loggedIn
        : localProfile;
    final nextResolvedKey = authState.isLoggedIn
        ? _authContextKey(authState)
        : localProfile == DocumentRequestProfile.anonymous
        ? 'anonymous'
        : null;
    final previousKey = _lastResolvedAuthContextKey;
    final currentProfile = ref
        .read(forumHomeControllerProvider)
        .asData
        ?.value
        .requestProfile;

    var shouldSwitch =
        currentProfile != null && currentProfile != effectiveProfile;
    if (previousKey == null) {
      if (nextResolvedKey != null) {
        _lastResolvedAuthContextKey = nextResolvedKey;
      }
    } else if (nextResolvedKey != null && previousKey != nextResolvedKey) {
      _lastResolvedAuthContextKey = nextResolvedKey;
      shouldSwitch = true;
    }

    // A failed profile probe is not proof of logout while a persisted auth
    // cookie still exists. Keep the verified UID and cached logged-in page;
    // an explicit logout clears the cookie and resolves to anonymous above.
    if (!authState.isLoggedIn &&
        localProfile == DocumentRequestProfile.loggedIn) {
      shouldSwitch = currentProfile == DocumentRequestProfile.anonymous;
    }
    if (!shouldSwitch || _isHandlingAuthContextChange) {
      return;
    }
    await _handleAuthContextChanged();
  }

  Future<void> _handleAuthContextChanged() async {
    if (!mounted || _isHandlingAuthContextChange) {
      return;
    }
    _isHandlingAuthContextChange = true;
    setState(() => _isSwitchingAuthContext = true);
    try {
      await ref
          .read(nativePageCacheInvalidationServiceProvider)
          .invalidateForumHome();
      ref.invalidate(forumHomeControllerProvider);
      // Keep the old account's content hidden until the replacement profile
      // has produced its own cache or network result.
      try {
        await ref.read(forumHomeControllerProvider.future);
      } catch (_) {
        // AsyncNotifier retains the failure for the normal error view.
      }
    } finally {
      _isHandlingAuthContextChange = false;
      if (mounted) {
        setState(() {
          _isSwitchingAuthContext = false;
        });
      }
    }
  }

  Future<void> _handleMoreMenuSelected(
    BuildContext context,
    String action,
  ) async {
    switch (action) {
      case _refreshPageAction:
        await ref
            .read(forumHomeControllerProvider.notifier)
            .refresh(forceNetwork: true);
        return;
      case _unfavoriteAction:
        await _openFavoriteForumPicker(context);
        return;
    }
  }

  Future<void> _openFavoriteForumPicker(BuildContext context) {
    final repository = ref.read(forumFavoriteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => ForumFavoriteForumPicker(
        loadFavoriteForums: repository.loadFavoriteForums,
        onUnfavorite: (forum) => repository.unfavoriteForum(favid: forum.favid),
        onSuccess: (_, _) async {
          if (!mounted || !messenger.mounted) {
            return;
          }
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(l10n.forumUnfavoriteSuccess)),
            );
          await ref
              .read(forumHomeControllerProvider.notifier)
              .refresh(forceNetwork: true);
        },
      ),
    );
  }

  Future<void> _triggerSilentRefreshIfNeeded() async {
    if (!mounted) {
      return;
    }
    final state = ref.read(forumHomeControllerProvider);
    final current = state.asData?.value;
    if (current == null || current.isRefreshing) {
      return;
    }
    final now = ref.read(forumHomeNowProvider).call();
    final elapsed = now.difference(current.lastUpdatedAt);
    if (elapsed < _forumHomeSilentRefreshThreshold) {
      return;
    }
    await ref
        .read(forumHomeControllerProvider.notifier)
        .refresh(forceNetwork: true);
  }

  String _authContextKey(AuthSessionViewState state) {
    if (!state.isLoggedIn) {
      return 'anonymous';
    }
    return 'logged_in:${state.uid.trim()}';
  }
}

class _ResolvedForumHomeBody extends ConsumerWidget {
  const _ResolvedForumHomeBody({
    required this.imageHeaderBuilder,
    required this.isActive,
  });

  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen<AsyncValue<ForumHomePageState>>(forumHomeControllerProvider, (
      previous,
      next,
    ) {
      final previousNotice = previous?.asData?.value.refreshNotice;
      final nextNotice = next.asData?.value.refreshNotice;
      if (nextNotice == null ||
          (nextNotice.code == previousNotice?.code &&
              nextNotice.detail == previousNotice?.detail)) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(ForumTextResolver.homeNotice(l10n, nextNotice)),
          ),
        );
    });

    final state = ref.watch(forumHomeControllerProvider);
    final mode = ref.watch(appServerContentConversionModeProvider);
    final projectionAsync = ref.watch(forumHomeContentProjectionProvider);
    return state.when(
      loading: () => const _ForumHomeBlankBody(),
      error: (error, _) => _ForumHomeErrorView(
        message: ForumTextResolver.homeLoadFailure(l10n, error),
        onRetry: () => ref
            .read(forumHomeControllerProvider.notifier)
            .refresh(forceNetwork: true),
      ),
      data: (data) => _ForumHomeContent(
        state: data,
        projection: _projectionOrRaw(
          data.viewData,
          mode: mode,
          candidate: projectionAsync.asData?.value,
        ),
        imageHeaderBuilder: imageHeaderBuilder,
        isActive: isActive,
      ),
    );
  }

  ForumHomeContentProjection _projectionOrRaw(
    ForumHomeViewData source, {
    required TextConversionMode mode,
    required ForumHomeContentProjection? candidate,
  }) {
    final revision = ForumHomeContentProjector.sourceRevisionFor(source);
    if (candidate != null &&
        candidate.mode == mode &&
        candidate.sourceRevision == revision) {
      return candidate;
    }
    return ForumHomeContentProjection.raw(source, mode: mode);
  }
}

class _ForumHomeContent extends ConsumerStatefulWidget {
  const _ForumHomeContent({
    required this.state,
    required this.projection,
    required this.imageHeaderBuilder,
    required this.isActive,
  });

  final ForumHomePageState state;
  final ForumHomeContentProjection projection;
  final ImageRequestHeaderBuilder imageHeaderBuilder;
  final bool isActive;

  @override
  ConsumerState<_ForumHomeContent> createState() => _ForumHomeContentState();
}

class _ForumHomeContentState extends ConsumerState<_ForumHomeContent> {
  final Set<String> _collapsedSectionKeys = <String>{};

  @override
  void didUpdateWidget(covariant _ForumHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeKeys = {
      for (final section in widget.projection.sections) _sectionKey(section),
    };
    _collapsedSectionKeys.removeWhere((key) => !activeKeys.contains(key));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ForumHomeNativePalette.resolve(Theme.of(context));
    return RefreshIndicator(
      onRefresh: () => ref
          .read(forumHomeControllerProvider.notifier)
          .refresh(forceNetwork: true),
      child: Stack(
        children: [
          ColoredBox(
            color: palette.background,
            child: ListView(
              key: const Key('forum-home-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 10),
              children: [
                ForumHomeCarousel(
                  items: widget.state.viewData.carouselItems,
                  headerBuilder: widget.imageHeaderBuilder,
                  onOpen: (item) => _openCarouselTarget(context, ref, item),
                  isActive: widget.isActive,
                ),
                if (widget.state.viewData.sections.isEmpty &&
                    widget.state.viewData.carouselItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(l10n.forumHomeEmpty)),
                  ),
                for (final section in widget.projection.sections)
                  ForumHomeSectionCard(
                    sectionKey: _sectionKey(section),
                    title:
                        section.displayTitle ??
                        ForumTextResolver.sectionTitle(l10n, section.source),
                    isCollapsed: _collapsedSectionKeys.contains(
                      _sectionKey(section),
                    ),
                    onToggle: () => _toggleSection(section),
                    children: _buildRows(context, section, l10n),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSection(ForumHomeSectionProjection section) {
    final key = _sectionKey(section);
    setState(() {
      if (!_collapsedSectionKeys.add(key)) {
        _collapsedSectionKeys.remove(key);
      }
    });
  }

  String _sectionKey(ForumHomeSectionProjection section) {
    return section.source.sourceIdentity;
  }

  List<Widget> _buildRows(
    BuildContext context,
    ForumHomeSectionProjection section,
    AppLocalizations l10n,
  ) {
    final rows = <_ForumHomeRowData>[
      for (final forum in section.items)
        _ForumHomeRowData(
          key: Key(
            section.source.type == ForumSectionType.favorite
                ? 'forum-favorite-card-${forum.source.fid}'
                : 'forum-card-${forum.source.fid}',
          ),
          title: forum.displayTitle,
          description: forum.displayDescription,
          todayPosts: forum.source.todayPosts,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ForumDisplayPage(
                  fid: forum.source.fid,
                  title: forum.source.title,
                ),
              ),
            );
          },
        ),
    ];

    return [
      for (var index = 0; index < rows.length; index++)
        ForumHomeForumRow(
          key: rows[index].key,
          title: rows[index].title,
          description: rows[index].description,
          todayPosts: rows[index].todayPosts,
          todayLabel: l10n.forumDisplayToday,
          isLast: index == rows.length - 1,
          onTap: rows[index].onTap,
        ),
    ];
  }

  Future<void> _openCarouselTarget(
    BuildContext context,
    WidgetRef ref,
    ForumHomeCarouselItem item,
  ) async {
    final parser = const ForumThreadUrlParser();
    final normalized = parser.normalizeHref(item.targetUrl);
    final tid = normalized == null ? null : parser.extractTid(normalized);
    if (tid != null && tid.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ThreadDetailPage(tid: tid)),
      );
      return;
    }

    final uri = ref.read(forumWebViewNavigatorProvider).resolve(item.targetUrl);
    await ref.read(forumWebViewExternalLauncherProvider).launch(uri);
  }
}

class _ForumHomeBlankBody extends StatelessWidget {
  const _ForumHomeBlankBody();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(key: Key('forum-home-blank-body'));
  }
}

class _ForumHomeRowData {
  const _ForumHomeRowData({
    required this.key,
    required this.title,
    required this.description,
    required this.todayPosts,
    required this.onTap,
  });

  final Key key;
  final String title;
  final String description;
  final int? todayPosts;
  final VoidCallback onTap;
}

class _ForumHomeErrorView extends StatelessWidget {
  const _ForumHomeErrorView({required this.message, required this.onRetry});

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
              key: const Key('forum-home-retry-button'),
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
