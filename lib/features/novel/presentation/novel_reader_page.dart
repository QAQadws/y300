import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_spacing.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/data/services/novel_reader_progress_diagnostics.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_paged_indicator_layout.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_display_settings_sheet.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_delayed_loading_boundary.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_image_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

const _progressDiagnostics = NovelReaderProgressDiagnostics();

class NovelReaderPage extends ConsumerStatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.novelId,
    required this.initialEpisodeId,
    this.openPolicy = NovelEpisodeOpenPolicy.resumeLastRead,
  });

  final String novelId;
  final String initialEpisodeId;
  final NovelEpisodeOpenPolicy openPolicy;

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage>
    with WidgetsBindingObserver {
  late final ScrollController _scrollController;
  late final ReaderOverlayController _overlayController;
  late final ReaderGestureCoordinator _readerGestureCoordinator;
  late final NovelReaderPagedNavigationController _pagedNavigationController;
  final NovelReaderThemeResolver _themeResolver =
      const NovelReaderThemeResolver();
  final NovelReaderTypographyResolver _typographyResolver =
      const NovelReaderTypographyResolver();
  final NovelReaderProgressPolicy _progressPolicy =
      const NovelReaderProgressPolicy();
  Timer? _displayPreviewThrottle;
  Timer? _displayPersistDebounce;
  NovelReaderPreferences? _pendingDisplayPreferences;
  NovelReaderPreferences? _lastPreviewedDisplayPreferences;
  NovelReaderPreferences? _lastPersistedDisplayPreferences;
  NovelReaderPreferences? _inFlightDisplayPreferences;
  int _displayPersistSerial = 0;
  int _readerSemanticsSuspendCount = 0;
  bool _hasRestoredOffset = false;
  String? _verticalRestoreOwner;
  String? _verticalContentReadyOwner;
  String? _verticalRestoreScheduledOwner;
  String? _verticalRenderThemeOwner;
  String? _verticalRenderThemeSignature;
  double? _pendingVerticalThemeRestoreOffset;
  bool _isProgrammaticScrollChange = false;
  bool _allowPopAfterProgressFlush = false;
  bool _isHandlingPop = false;
  int _pageSeekSerial = 0;
  int _chapterEntrySerial = 0;
  NovelReaderChapterEntryRequest? _pendingChapterEntryRequest;
  NovelReaderPageSeekRequest? _pendingPageSeekRequest;
  NovelReaderPaginationPosition? _pagedPosition;
  double? _progressSliderPreview;
  bool _isProgressSeekInFlight = false;
  String? _progressControlOwner;
  String? _readyReaderSurfaceIdentity;

  NovelReaderArgs get _args => NovelReaderArgs(
    novelId: widget.novelId,
    episodeId: widget.initialEpisodeId,
    openPolicy: widget.openPolicy,
  );

  @override
  void initState() {
    super.initState();
    _progressDiagnostics.log(
      'page_open',
      fields: <String, Object?>{
        'novelId': widget.novelId,
        'episodeId': widget.initialEpisodeId,
        'openPolicy': widget.openPolicy.name,
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _overlayController = ReaderOverlayController();
    _readerGestureCoordinator = ReaderGestureCoordinator(
      doubleTapTimeout: ReaderPagedTurnMotion.tapConfirmationDelay,
    );
    _pagedNavigationController = NovelReaderPagedNavigationController();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayController.dispose();
    _readerGestureCoordinator.dispose();
    _pagedNavigationController.dispose();
    _displayPreviewThrottle?.cancel();
    _displayPersistDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_saveVisibleProgressNow(reason: 'lifecycle_${state.name}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(novelReaderControllerProvider(_args));
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);
    final externalLauncher = ref.watch(forumWebViewExternalLauncherProvider);

    return PopScope<void>(
      canPop: _allowPopAfterProgressFlush,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        unawaited(_flushProgressAndPop());
      },
      child: Scaffold(
        body: state.when(
          loading: () {
            _readyReaderSurfaceIdentity = null;
            final backgroundColor = Theme.of(context).colorScheme.surface;
            return NovelReaderDelayedLoadingBoundary(
              identity: 'initial-reader-load',
              isLoading: true,
              backgroundColor: backgroundColor,
              child: ColoredBox(color: backgroundColor),
            );
          },
          error: (error, _) {
            return NovelReaderErrorView(
              error: error,
              onRetry: () =>
                  ref.invalidate(novelReaderControllerProvider(_args)),
              onUpdateWork: () => _updateWorkFromErrorView(),
              onOpenThread: () => _openFallbackSourceThread(),
            );
          },
          data: (viewState) {
            final systemPadding = MediaQuery.paddingOf(context);
            final readerSurfaceIdentity = _readerSurfaceIdentity(viewState);
            final restoreOwner = _verticalRestoreOwnerFor(
              readerSurfaceIdentity,
            );
            final safeAreaTop = viewState.preferences.safeAreaEnabled
                ? systemPadding.top
                : 0.0;
            final safeAreaBottom = viewState.preferences.safeAreaEnabled
                ? systemPadding.bottom
                : 0.0;
            final paginationGeometryOwner =
                '$readerSurfaceIdentity|'
                '${NovelReaderPaginationKey.logicalPixels(safeAreaTop)}|'
                '${NovelReaderPaginationKey.logicalPixels(safeAreaBottom)}';
            if (_progressControlOwner != paginationGeometryOwner) {
              _readerGestureCoordinator.cancelPendingTap();
              _progressControlOwner = paginationGeometryOwner;
              _pagedPosition = null;
              _pendingPageSeekRequest = null;
              _progressSliderPreview = null;
              _isProgressSeekInFlight = false;
              // The owner flips exactly when a switched-to chapter arrives, so
              // an entry request for *this* episode is the one that just landed
              // and must survive. Anything else means the reader went somewhere
              // that request no longer describes (catalog jump, mode switch).
              if (_pendingChapterEntryRequest?.episodeId !=
                  viewState.currentEpisode.episodeId) {
                _pendingChapterEntryRequest = null;
              }
            }
            if (_verticalRestoreOwner != restoreOwner) {
              _verticalRestoreOwner = restoreOwner;
              _verticalContentReadyOwner = null;
              _verticalRestoreScheduledOwner = null;
              _hasRestoredOffset = false;
              _progressDiagnostics.log(
                'surface_owner',
                fields: <String, Object?>{
                  'novelId': widget.novelId,
                  'owner': restoreOwner,
                  'openPolicy': widget.openPolicy.name,
                  'snapshotOffset': viewState.progressSnapshot.scrollOffset
                      .toStringAsFixed(2),
                  'snapshotPercent': viewState.progressSnapshot.progressPercent
                      .toStringAsFixed(4),
                  'snapshotFlowMode': viewState.progressSnapshot.flowMode.name,
                },
              );
            }
            final theme = Theme.of(context);
            final palette = _themeResolver.resolve(
              preferences: viewState.preferences,
              theme: theme,
            );
            final typography = _typographyResolver.resolve(
              preferences: viewState.preferences,
              theme: theme,
              palette: palette,
            );
            final readerIsLoading =
                viewState.transition != null ||
                _readyReaderSurfaceIdentity != readerSurfaceIdentity;
            return ColoredBox(
              key: const Key('novel-reader-background'),
              color: palette.background,
              child: Builder(
                builder: (context) {
                  final reader = ReaderOverlayScaffold(
                    controller: _overlayController,
                    gestureCoordinator: _readerGestureCoordinator,
                    topBar: _buildTopBarConfig(viewState),
                    bottomBar: _buildBottomBarConfig(viewState, controller),
                    bottomSafeFraction: 0.18,
                    onLeftTap:
                        viewState.preferences.flowMode ==
                            NovelReaderFlowMode.vertical
                        ? null
                        : () => _turnPagedByPhysicalTap(
                            surfaceIdentity: readerSurfaceIdentity,
                            isLeftTap: true,
                          ),
                    onRightTap:
                        viewState.preferences.flowMode ==
                            NovelReaderFlowMode.vertical
                        ? null
                        : () => _turnPagedByPhysicalTap(
                            surfaceIdentity: readerSurfaceIdentity,
                            isLeftTap: false,
                          ),
                    child: _buildReaderList(
                      viewState,
                      typography,
                      const NovelForumHtmlRenderThemeFactory().fromPalette(
                        palette,
                      ),
                      imageHeaderBuilder,
                      externalLauncher,
                      ReaderChromeInsets(
                        safeAreaTop: safeAreaTop,
                        safeAreaBottom: safeAreaBottom,
                        pageIndicatorReservedHeight:
                            viewState.preferences.showProgressIndicator
                            ? NovelReaderPagedIndicatorLayout.reservedHeight(
                                MediaQuery.textScalerOf(context),
                              )
                            : 0,
                      ),
                      surfaceIdentity: readerSurfaceIdentity,
                    ),
                  );
                  final loadingIdentity =
                      viewState.transition?.targetEpisodeId ??
                      viewState.currentEpisode.episodeId;
                  return NovelReaderDelayedLoadingBoundary(
                    identity: loadingIdentity,
                    isLoading: readerIsLoading,
                    backgroundColor: palette.background,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ExcludeSemantics(
                            excluding: _readerSemanticsSuspendCount > 0,
                            child: KeyedSubtree(
                              key: ValueKey<String>(readerSurfaceIdentity),
                              child: reader,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _readerSurfaceIdentity(NovelReaderViewState viewState) {
    return '${viewState.currentEpisode.episodeId}|'
        '${viewState.document.rawHtmlHash}|'
        '${viewState.preferences.flowMode.name}|'
        '${viewState.preferences.hashCode}';
  }

  String _verticalRestoreOwnerFor(String surfaceIdentity) {
    return '$surfaceIdentity|vertical-restore';
  }

  void _markReaderSurfaceReady(String identity, {bool terminal = false}) {
    if (!_isCurrentReaderSurface(identity) ||
        _readyReaderSurfaceIdentity == identity) {
      return;
    }
    setState(() {
      _readyReaderSurfaceIdentity = identity;
    });
    if (terminal) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final latest = ref
          .read(novelReaderControllerProvider(_args))
          .asData
          ?.value;
      if (latest == null ||
          latest.transition != null ||
          _readerSurfaceIdentity(latest) != identity ||
          latest.preferences.flowMode != NovelReaderFlowMode.vertical) {
        return;
      }
      _restoreVerticalOffsetAfterContentReady(
        owner: _verticalRestoreOwnerFor(identity),
        episodeId: latest.currentEpisode.episodeId,
      );
    });
  }

  bool _isCurrentReaderSurface(String identity) {
    if (!mounted) {
      return false;
    }
    final current = ref
        .read(novelReaderControllerProvider(_args))
        .asData
        ?.value;
    return current != null && _readerSurfaceIdentity(current) == identity;
  }

  void _turnPagedByPhysicalTap({
    required String surfaceIdentity,
    required bool isLeftTap,
  }) {
    if (!mounted) {
      return;
    }
    final current = ref
        .read(novelReaderControllerProvider(_args))
        .asData
        ?.value;
    if (current == null ||
        current.transition != null ||
        current.preferences.flowMode == NovelReaderFlowMode.vertical ||
        _readerSurfaceIdentity(current) != surfaceIdentity) {
      return;
    }
    final isRtl = current.preferences.flowMode == NovelReaderFlowMode.pagedRtl;
    final isPrevious = isRtl ? !isLeftTap : isLeftTap;
    if (isPrevious) {
      _pagedNavigationController.turnPrevious();
    } else {
      _pagedNavigationController.turnNext();
    }
  }

  void _cancelPendingReaderTap() {
    _readerGestureCoordinator.cancelPendingTap();
  }

  ReaderTopBarConfig _buildTopBarConfig(NovelReaderViewState viewState) {
    final l10n = AppLocalizations.of(context);
    return ReaderTopBarConfig(
      title: _novelTitle(viewState),
      subtitle: NovelTextResolver.chapterTitle(
        l10n,
        viewState.currentEpisode.episodeTitle,
        viewState.currentEpisode.sourceTid,
      ),
      onBack: () => _popReader(),
      actions: [
        ReaderToolbarAction(
          id: 'bookmark',
          icon: viewState.hasCurrentEpisodeBookmark
              ? Icons.bookmark
              : Icons.bookmark_border,
          label: viewState.hasCurrentEpisodeBookmark
              ? l10n.novelBookmarkRemove
              : l10n.novelBookmarkAdd,
          onPressed: () => _toggleEpisodeBookmark(viewState),
        ),
        ReaderToolbarAction(
          id: 'open-thread',
          icon: Icons.open_in_new,
          label: l10n.novelOpenSourceThread,
          onPressed: () => _openSourceThread(viewState),
        ),
      ],
    );
  }

  ReaderBottomBarConfig _buildBottomBarConfig(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    return ReaderBottomBarConfig(
      progress: _buildProgressConfig(viewState, controller),
      actions: _buildBottomActions(viewState, controller),
    );
  }

  ReaderProgressConfig _buildProgressConfig(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    final l10n = AppLocalizations.of(context);
    final isLocked = viewState.transition != null || _isProgressSeekInFlight;
    final onPrevious = viewState.hasPreviousEpisode
        ? () => unawaited(_openDifferentEpisode(controller.goToPreviousEpisode))
        : null;
    final onNext = viewState.hasNextEpisode
        ? () => unawaited(_openDifferentEpisode(controller.goToNextEpisode))
        : null;
    if (viewState.preferences.flowMode == NovelReaderFlowMode.vertical) {
      final fraction =
          (_progressSliderPreview ?? viewState.progressSnapshot.progressPercent)
              .clamp(0.0, 1.0)
              .toDouble();
      return ReaderProgressConfig.continuous(
        value: fraction,
        leadingLabel: '${(fraction * 100).floor()}%',
        trailingLabel: '100%',
        interactionLocked: isLocked,
        previousEnabled: viewState.hasPreviousEpisode && !isLocked,
        nextEnabled: viewState.hasNextEpisode && !isLocked,
        onPrevious: onPrevious,
        onNext: onNext,
        onChangeStart: _previewProgressSlider,
        onChanged: _previewProgressSlider,
        onChangeEnd: (value) =>
            unawaited(_seekVerticalProgress(value, viewState, controller)),
      );
    }

    final position = _pagedPosition;
    final isFinal =
        position?.episodeId == viewState.currentEpisode.episodeId &&
        position?.isPageCountFinal == true;
    final total = isFinal
        ? position!.pageCount
        : (viewState.progressSnapshot.pageCount ?? 1);
    final currentIndex =
        (_progressSliderPreview?.round() ??
                (position?.pageIndex ?? viewState.progressSnapshot.pageIndex))
            .clamp(0, total - 1)
            .toInt();
    return ReaderProgressConfig.discrete(
      current: currentIndex + 1,
      total: total,
      leadingLabel: '${currentIndex + 1}',
      trailingLabel: isFinal ? '$total' : l10n.novelPageCountPending,
      sliderEnabled: isFinal,
      interactionLocked: isLocked,
      previousEnabled: viewState.hasPreviousEpisode && !isLocked,
      nextEnabled: viewState.hasNextEpisode && !isLocked,
      onPrevious: onPrevious,
      onNext: onNext,
      onChangeStart: _previewProgressSlider,
      onChanged: _previewProgressSlider,
      onChangeEnd: (value) => _seekPagedProgress(value, viewState),
    );
  }

  List<ReaderToolbarAction> _buildBottomActions(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) {
    final l10n = AppLocalizations.of(context);
    return [
      ReaderToolbarAction(
        id: 'catalog',
        icon: Icons.format_list_bulleted,
        label: l10n.novelCatalog,
        onPressed: () => _showChapterListSheet(viewState, controller),
      ),
      ReaderToolbarAction(
        id: 'display',
        icon: Icons.tune,
        label: l10n.novelDisplay,
        onPressed: () => _showDisplaySettingsSheet(viewState, controller),
      ),
    ];
  }

  void _previewProgressSlider(double value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _progressSliderPreview = value;
    });
  }

  Future<void> _seekVerticalProgress(
    double value,
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    if (!_scrollController.hasClients || _isProgressSeekInFlight) {
      if (mounted) {
        setState(() => _progressSliderPreview = null);
      }
      return;
    }
    final fraction = value.clamp(0.0, 1.0).toDouble();
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final targetOffset = fraction * maxScrollExtent;
    _progressDiagnostics.log(
      'slider_seek',
      fields: <String, Object?>{
        'novelId': widget.novelId,
        'episodeId': viewState.currentEpisode.episodeId,
        'targetPercent': fraction.toStringAsFixed(4),
        'targetOffset': targetOffset.toStringAsFixed(2),
        'maxScrollExtent': maxScrollExtent.toStringAsFixed(2),
      },
    );
    setState(() {
      _isProgressSeekInFlight = true;
      _progressSliderPreview = fraction;
    });
    _isProgrammaticScrollChange = true;
    try {
      _scrollController.jumpTo(targetOffset);
      await controller.saveCurrentProgressNow(
        _progressPolicy.verticalSnapshot(
          novelId: widget.novelId,
          episodeId: viewState.currentEpisode.episodeId,
          scrollOffset: targetOffset,
          maxScrollExtent: maxScrollExtent,
        ),
      );
    } finally {
      _isProgrammaticScrollChange = false;
      if (mounted) {
        setState(() {
          _isProgressSeekInFlight = false;
          _progressSliderPreview = null;
        });
      }
    }
  }

  void _seekPagedProgress(double value, NovelReaderViewState viewState) {
    final position = _pagedPosition;
    if (_isProgressSeekInFlight ||
        position == null ||
        !position.isPageCountFinal ||
        position.episodeId != viewState.currentEpisode.episodeId) {
      if (mounted) {
        setState(() => _progressSliderPreview = null);
      }
      return;
    }
    final targetIndex = value.round().clamp(0, position.pageCount - 1).toInt();
    setState(() {
      _isProgressSeekInFlight = true;
      _progressSliderPreview = targetIndex.toDouble();
      _pendingPageSeekRequest = NovelReaderPageSeekRequest(
        requestId: ++_pageSeekSerial,
        episodeId: position.episodeId,
        paginationKey: position.paginationKey,
        pageIndex: targetIndex,
      );
    });
  }

  Widget _buildReaderList(
    NovelReaderViewState viewState,
    NovelReaderTypography typography,
    ForumHtmlThemeContext htmlTheme,
    ImageRequestHeaderBuilder imageHeaderBuilder,
    ForumWebViewExternalLauncher externalLauncher,
    ReaderChromeInsets chromeInsets, {
    required String surfaceIdentity,
  }) {
    if (viewState.preferences.flowMode != NovelReaderFlowMode.vertical) {
      return NovelReaderHtmlPagedSurface(
        rawHtml: viewState.currentContent.rawHtml,
        episode: viewState.currentEpisode,
        preferences: viewState.preferences,
        typography: typography,
        theme: htmlTheme,
        imageReferer: _imageRefererFor(viewState),
        progressSnapshot: viewState.progressSnapshot,
        chromeInsets: chromeInsets,
        semanticDocument: viewState.document,
        pageSeekRequest: _pendingPageSeekRequest,
        navigationController: _pagedNavigationController,
        chapterEntryRequest: _pendingChapterEntryRequest,
        onChapterEntryApplied: (request) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _retireChapterEntryRequest(requestId: request.requestId);
          }
        },
        previousChapterTitle: viewState.previousEpisode?.episodeTitle,
        nextChapterTitle: viewState.nextEpisode?.episodeTitle,
        onTurnToAdjacentChapter: (edge) {
          if (!_isCurrentReaderSurface(surfaceIdentity)) {
            return false;
          }
          return _turnToAdjacentChapter(edge, viewState);
        },
        imageHeaderBuilder: imageHeaderBuilder,
        onContentReady: () => _markReaderSurfaceReady(surfaceIdentity),
        onContentTerminal: () =>
            _markReaderSurfaceReady(surfaceIdentity, terminal: true),
        onLinkTap: (link) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _openReaderLink(link, externalLauncher);
          }
        },
        onOpenImage: (request) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _openHtmlReaderImage(request);
          }
        },
        onImageFallback: (request) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _copyNovelImageUrl(request.url);
          }
        },
        onContentInteraction: _cancelPendingReaderTap,
        onFallbackToVertical: () {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _fallbackToVertical(
              ref.read(novelReaderControllerProvider(_args).notifier),
            );
          }
        },
        onPositionChanged: (position) {
          if (!_isCurrentReaderSurface(surfaceIdentity)) {
            return;
          }
          setState(() {
            _pagedPosition = position;
            final pending = _pendingPageSeekRequest;
            if (pending != null &&
                pending.episodeId == position.episodeId &&
                pending.paginationKey == position.paginationKey &&
                pending.pageIndex == position.pageIndex) {
              _pendingPageSeekRequest = null;
              _progressSliderPreview = null;
              _isProgressSeekInFlight = false;
            }
          });
          _overlayController.hideMenu();
          ref
              .read(novelReaderControllerProvider(_args).notifier)
              .onPagedPositionChanged(position);
        },
        onNavigationUnavailable: (_) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _showReaderSnackBar(
              AppLocalizations.of(context).novelPositionChanged,
            );
          }
        },
      );
    }
    final restoreOwner = _verticalRestoreOwnerFor(surfaceIdentity);
    _trackVerticalRenderTheme(
      owner: restoreOwner,
      themeSignature: htmlTheme.signature,
    );
    final children = <Widget>[
      NovelReaderHtmlDocumentView(
        rawHtml: viewState.currentContent.rawHtml,
        episode: viewState.currentEpisode,
        preferences: viewState.preferences,
        typography: typography,
        theme: htmlTheme,
        imageReferer: _imageRefererFor(viewState),
        imageHeaderBuilder: imageHeaderBuilder,
        onLinkTap: (link) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _openReaderLink(link, externalLauncher);
          }
        },
        onOpenImage: (request) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _openHtmlReaderImage(request);
          }
        },
        onImageFallback: (request) {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            _copyNovelImageUrl(request.url);
          }
        },
        onContentInteraction: _cancelPendingReaderTap,
        onContentReady: () {
          _restoreVerticalOffsetAfterThemeUpdate(
            owner: restoreOwner,
            themeSignature: htmlTheme.signature,
          );
          _markReaderSurfaceReady(surfaceIdentity);
        },
        onContentTerminal: () {
          _clearPendingVerticalThemeRestore(
            owner: restoreOwner,
            themeSignature: htmlTheme.signature,
          );
          _markReaderSurfaceReady(surfaceIdentity, terminal: true);
        },
        onRetry: () {
          if (_isCurrentReaderSurface(surfaceIdentity)) {
            ref.invalidate(novelReaderControllerProvider(_args));
          }
        },
      ),
      if (viewState.nextEpisode != null) ...[
        SizedBox(height: viewState.preferences.paragraphSpacing * 2),
        NovelReaderNextChapterTransition(
          nextEpisode: viewState.nextEpisode!,
          onPressed: () {
            if (_isCurrentReaderSurface(surfaceIdentity)) {
              _openDifferentEpisode(
                () => ref
                    .read(novelReaderControllerProvider(_args).notifier)
                    .goToNextEpisode(),
              );
            }
          },
        ),
      ],
    ];
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification is ScrollStartNotification &&
            notification.dragDetails != null &&
            !_hasRestoredOffset) {
          _hasRestoredOffset = true;
          _verticalRestoreScheduledOwner = null;
          _progressDiagnostics.log(
            'restore_cancel',
            fields: <String, Object?>{
              'novelId': widget.novelId,
              'episodeId': viewState.currentEpisode.episodeId,
              'reason': 'user_scroll_started',
            },
          );
        }
        return false;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _scheduleVerticalRestoreAttempt(
              owner: restoreOwner,
              episodeId: viewState.currentEpisode.episodeId,
              trigger: 'metrics_changed',
            );
          }
          return false;
        },
        child: ListView(
          key: const Key('novel-reader-paragraph-list'),
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            NovelReaderSpacing.verticalPagePadding,
            NovelReaderSpacing.verticalPagePadding + chromeInsets.topInset,
            NovelReaderSpacing.verticalPagePadding,
            NovelReaderSpacing.verticalPagePadding +
                chromeInsets.persistentBottomInset,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                key: const Key('novel-reader-content-column'),
                constraints: BoxConstraints(
                  maxWidth: _safeContentMaxWidth(typography),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_isProgrammaticScrollChange) {
      return;
    }
    if (_pendingVerticalThemeRestoreOffset != null) {
      return;
    }
    if (!_hasRestoredOffset) {
      // Ignore layout-driven position notifications until either restoration
      // succeeds or a real drag explicitly takes ownership of the position.
      return;
    }
    _overlayController.hideMenu();
    ref
        .read(novelReaderControllerProvider(_args).notifier)
        .onScrollOffsetChanged(
          _scrollController.offset,
          maxScrollExtent: _scrollController.position.maxScrollExtent,
        );
  }

  void _trackVerticalRenderTheme({
    required String owner,
    required String themeSignature,
  }) {
    if (_verticalRenderThemeOwner != owner) {
      _verticalRenderThemeOwner = owner;
      _verticalRenderThemeSignature = themeSignature;
      _pendingVerticalThemeRestoreOffset = null;
      return;
    }
    if (_verticalRenderThemeSignature == themeSignature) {
      return;
    }
    _verticalRenderThemeSignature = themeSignature;
    if (_pendingVerticalThemeRestoreOffset == null &&
        _scrollController.hasClients &&
        _hasRestoredOffset) {
      _pendingVerticalThemeRestoreOffset = _scrollController.offset;
    }
  }

  void _restoreVerticalOffsetAfterThemeUpdate({
    required String owner,
    required String themeSignature,
  }) {
    final offset = _pendingVerticalThemeRestoreOffset;
    if (!mounted ||
        offset == null ||
        _verticalRenderThemeOwner != owner ||
        _verticalRenderThemeSignature != themeSignature ||
        !_scrollController.hasClients) {
      return;
    }
    final max = _scrollController.position.maxScrollExtent;
    final restoredOffset = offset.clamp(0.0, max).toDouble();
    _isProgrammaticScrollChange = true;
    try {
      _scrollController.jumpTo(restoredOffset);
    } finally {
      _isProgrammaticScrollChange = false;
      _pendingVerticalThemeRestoreOffset = null;
    }
    unawaited(
      ref
          .read(novelReaderControllerProvider(_args).notifier)
          .onScrollOffsetChanged(restoredOffset, maxScrollExtent: max),
    );
  }

  void _clearPendingVerticalThemeRestore({
    required String owner,
    required String themeSignature,
  }) {
    if (_verticalRenderThemeOwner == owner &&
        _verticalRenderThemeSignature == themeSignature) {
      _pendingVerticalThemeRestoreOffset = null;
    }
  }

  void _restoreVerticalOffsetAfterContentReady({
    required String owner,
    required String episodeId,
  }) {
    if (!mounted || _verticalRestoreOwner != owner) {
      _progressDiagnostics.log(
        'html_ready_stale',
        fields: <String, Object?>{
          'novelId': widget.novelId,
          'episodeId': episodeId,
          'callbackOwner': owner,
          'activeOwner': _verticalRestoreOwner,
        },
      );
      return;
    }
    final current = ref.read(novelReaderControllerProvider(_args)).value;
    _progressDiagnostics.log(
      'html_ready',
      fields: <String, Object?>{
        'novelId': widget.novelId,
        'episodeId': episodeId,
        'owner': owner,
        'openPolicy': widget.openPolicy.name,
        'hasClients': _scrollController.hasClients,
        'currentOffset': _scrollController.hasClients
            ? _scrollController.offset.toStringAsFixed(2)
            : null,
        'maxScrollExtent': _scrollController.hasClients
            ? _scrollController.position.maxScrollExtent.toStringAsFixed(2)
            : null,
        'snapshotOffset': current?.progressSnapshot.scrollOffset
            .toStringAsFixed(2),
        'snapshotPercent': current?.progressSnapshot.progressPercent
            .toStringAsFixed(4),
        'snapshotFlowMode': current?.progressSnapshot.flowMode.name,
      },
    );
    if (current == null ||
        current.transition != null ||
        current.currentEpisode.episodeId != episodeId ||
        current.preferences.flowMode != NovelReaderFlowMode.vertical) {
      _progressDiagnostics.log(
        'restore_skip',
        fields: <String, Object?>{
          'novelId': widget.novelId,
          'episodeId': episodeId,
          'reason': 'state_mismatch',
        },
      );
      return;
    }
    _verticalContentReadyOwner = owner;
    if (_hasRestoredOffset) {
      _progressDiagnostics.log(
        'restore_skip',
        fields: <String, Object?>{
          'novelId': widget.novelId,
          'episodeId': episodeId,
          'reason': 'already_restored',
          'currentOffset': _scrollController.hasClients
              ? _scrollController.offset.toStringAsFixed(2)
              : null,
        },
      );
      _notifyVerticalContentReady(episodeId);
      return;
    }
    if (_scrollController.hasClients) {
      // The ready callback is already post-frame. Apply the initial position
      // against the measured list immediately; waiting for another callback
      // can leave the overlay menu hidden behind a pending restore frame.
      _verticalRestoreScheduledOwner = null;
      _attemptVerticalRestore(
        owner: owner,
        episodeId: episodeId,
        trigger: 'html_ready',
      );
      return;
    }
    _scheduleVerticalRestoreAttempt(
      owner: owner,
      episodeId: episodeId,
      trigger: 'html_ready',
    );
  }

  void _scheduleVerticalRestoreAttempt({
    required String owner,
    required String episodeId,
    required String trigger,
  }) {
    if (!mounted ||
        _verticalRestoreOwner != owner ||
        _verticalContentReadyOwner != owner ||
        _hasRestoredOffset) {
      return;
    }
    if (_verticalRestoreScheduledOwner == owner) {
      // A metrics notification may already have queued the callback before
      // the HTML-ready signal. Keep a frame scheduled so that callback is not
      // stranded after the current frame settles.
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _verticalRestoreScheduledOwner = owner;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalRestoreScheduledOwner == owner) {
        _verticalRestoreScheduledOwner = null;
      }
      _attemptVerticalRestore(
        owner: owner,
        episodeId: episodeId,
        trigger: trigger,
      );
    });
    // A post-frame callback does not itself request another frame. The first
    // ready callback can run after the current layout has settled, so request
    // one explicitly to measure the newly mounted list and apply percentage
    // restoration deterministically.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _attemptVerticalRestore({
    required String owner,
    required String episodeId,
    required String trigger,
  }) {
    if (!mounted ||
        _verticalRestoreOwner != owner ||
        _verticalContentReadyOwner != owner ||
        _hasRestoredOffset) {
      return;
    }
    final current = ref.read(novelReaderControllerProvider(_args)).value;
    if (current == null ||
        current.transition != null ||
        current.currentEpisode.episodeId != episodeId ||
        current.preferences.flowMode != NovelReaderFlowMode.vertical) {
      return;
    }
    final snapshot = current.progressSnapshot;
    if (snapshot.scrollOffset <= 0 &&
        snapshot.progressPercent <= 0 &&
        snapshot.paginationKey == null) {
      _hasRestoredOffset = true;
      _progressDiagnostics.log(
        'restore_beginning',
        fields: <String, Object?>{
          'novelId': widget.novelId,
          'episodeId': episodeId,
          'openPolicy': widget.openPolicy.name,
        },
      );
      _notifyVerticalContentReady(episodeId);
      return;
    }
    if (!_scrollController.hasClients) {
      _logVerticalRestoreWait(
        episodeId: episodeId,
        trigger: trigger,
        snapshot: snapshot,
        reason: 'no_scroll_clients',
      );
      return;
    }
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      _logVerticalRestoreWait(
        episodeId: episodeId,
        trigger: trigger,
        snapshot: snapshot,
        reason: 'empty_scroll_extent',
        maxScrollExtent: max,
      );
      return;
    }
    final offset = _progressPolicy.restoreScrollOffset(
      snapshot,
      maxScrollExtent: max,
      viewportDimension: _scrollController.position.viewportDimension,
    );
    _progressDiagnostics.log(
      'restore_apply',
      fields: <String, Object?>{
        'novelId': widget.novelId,
        'episodeId': episodeId,
        'trigger': trigger,
        'openPolicy': widget.openPolicy.name,
        'snapshotFlowMode': snapshot.flowMode.name,
        'snapshotOffset': snapshot.scrollOffset.toStringAsFixed(2),
        'snapshotPercent': snapshot.progressPercent.toStringAsFixed(4),
        'maxScrollExtent': max.toStringAsFixed(2),
        'viewportDimension': _scrollController.position.viewportDimension
            .toStringAsFixed(2),
        'targetOffset': offset.toStringAsFixed(2),
      },
    );
    _isProgrammaticScrollChange = true;
    try {
      _scrollController.jumpTo(offset.clamp(0.0, max).toDouble());
    } finally {
      _isProgrammaticScrollChange = false;
    }
    _hasRestoredOffset = true;
    unawaited(
      ref
          .read(novelReaderControllerProvider(_args).notifier)
          .onScrollOffsetChanged(offset, maxScrollExtent: max),
    );
    _notifyVerticalContentReady(episodeId);
  }

  void _logVerticalRestoreWait({
    required String episodeId,
    required String trigger,
    required NovelReaderProgressSnapshot snapshot,
    required String reason,
    double? maxScrollExtent,
  }) {
    _progressDiagnostics.log(
      'restore_wait',
      fields: <String, Object?>{
        'novelId': widget.novelId,
        'episodeId': episodeId,
        'trigger': trigger,
        'reason': reason,
        'snapshotOffset': snapshot.scrollOffset.toStringAsFixed(2),
        'snapshotPercent': snapshot.progressPercent.toStringAsFixed(4),
        'maxScrollExtent': maxScrollExtent?.toStringAsFixed(2),
      },
    );
  }

  void _notifyVerticalContentReady(String episodeId) {
    unawaited(
      ref
          .read(novelReaderControllerProvider(_args).notifier)
          .onVerticalContentReady(episodeId),
    );
  }

  Future<void> _popReader() async {
    await _flushProgressAndPop();
  }

  Future<void> _flushProgressAndPop() async {
    if (_isHandlingPop) {
      return;
    }
    _isHandlingPop = true;
    try {
      await _saveVisibleProgressNow(reason: 'route_pop');
      if (!mounted) {
        return;
      }
      _allowPopAfterProgressFlush = true;
      Navigator.of(context).pop();
    } finally {
      _isHandlingPop = false;
    }
  }

  /// Handles a page turn that ran past either end of the chapter.
  ///
  /// Forward lands on the next chapter's first page, which is the transition
  /// default. Backward has to land on the previous chapter's *last* page, so it
  /// arms an entry request that the paged surface resolves once that chapter's
  /// plan is complete and its page count is known.
  /// Returns whether the turn was accepted. The answer has to be synchronous:
  /// the paged surface locks its gesture on the strength of it, and a decline
  /// arms no entry request and therefore produces nothing that would unlock it.
  bool _turnToAdjacentChapter(
    NovelReaderChapterEdge edge,
    NovelReaderViewState viewState,
  ) {
    if (viewState.transition != null) {
      return false;
    }
    final target = edge == NovelReaderChapterEdge.end
        ? viewState.nextEpisode
        : viewState.previousEpisode;
    if (target == null) {
      return false;
    }
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    setState(() {
      _pendingChapterEntryRequest = NovelReaderChapterEntryRequest(
        requestId: ++_chapterEntrySerial,
        episodeId: target.episodeId,
        edge: edge == NovelReaderChapterEdge.end
            ? NovelReaderChapterEdge.start
            : NovelReaderChapterEdge.end,
      );
    });
    unawaited(_runChapterTurn(edge, controller));
    return true;
  }

  Future<void> _runChapterTurn(
    NovelReaderChapterEdge edge,
    NovelReaderController controller,
  ) async {
    final didSucceed = await _openDifferentEpisode(
      edge == NovelReaderChapterEdge.end
          ? controller.goToNextEpisode
          : controller.goToPreviousEpisode,
    );
    if (!didSucceed) {
      _retireChapterEntryRequest();
    }
  }

  /// Retires the armed entry request, which is what re-arms the turn gesture.
  /// Guarded by [requestId] so a stale completion cannot cancel a newer turn.
  void _retireChapterEntryRequest({int? requestId}) {
    if (!mounted) {
      return;
    }
    final request = _pendingChapterEntryRequest;
    if (request == null) {
      return;
    }
    if (requestId != null && request.requestId != requestId) {
      return;
    }
    setState(() => _pendingChapterEntryRequest = null);
  }

  Future<bool> _openDifferentEpisode(Future<bool> Function() action) async {
    await _saveVisibleProgressNow(reason: 'before_episode_switch');
    _hasRestoredOffset = false;
    if (_scrollController.hasClients) {
      _isProgrammaticScrollChange = true;
      try {
        _scrollController.jumpTo(0);
      } finally {
        _isProgrammaticScrollChange = false;
      }
    }
    _overlayController.hideMenu();
    final didSucceed = await action();
    if (!mounted || didSucceed) {
      return didSucceed;
    }
    _showReaderSnackBar(AppLocalizations.of(context).novelChapterSwitchFailed);
    return false;
  }

  Future<void> _saveVisibleProgressNow({required String reason}) async {
    final viewState = ref.read(novelReaderControllerProvider(_args)).value;
    if (viewState == null) {
      _progressDiagnostics.log(
        'visible_flush_skip',
        fields: <String, Object?>{
          'novelId': widget.novelId,
          'reason': reason,
          'cause': 'state_unavailable',
        },
      );
      return;
    }
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    if (viewState.preferences.flowMode != NovelReaderFlowMode.vertical) {
      _logVisibleFlush(reason: reason, snapshot: viewState.progressSnapshot);
      await controller.saveCurrentProgressNow(viewState.progressSnapshot);
      return;
    }
    if (!_scrollController.hasClients || !_hasRestoredOffset) {
      _logVisibleFlush(
        reason: reason,
        snapshot: viewState.progressSnapshot,
        hasClients: _scrollController.hasClients,
        hasRestoredOffset: _hasRestoredOffset,
      );
      await controller.saveCurrentProgressNow(viewState.progressSnapshot);
      return;
    }
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final maxScrollExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final snapshot = _progressPolicy.verticalSnapshot(
      novelId: widget.novelId,
      episodeId: viewState.currentEpisode.episodeId,
      scrollOffset: offset,
      maxScrollExtent: maxScrollExtent,
    );
    _logVisibleFlush(
      reason: reason,
      snapshot: snapshot,
      maxScrollExtent: maxScrollExtent,
      hasClients: true,
      hasRestoredOffset: _hasRestoredOffset,
    );
    await controller.saveCurrentProgressNow(snapshot);
  }

  void _logVisibleFlush({
    required String reason,
    required NovelReaderProgressSnapshot snapshot,
    double? maxScrollExtent,
    bool? hasClients,
    bool? hasRestoredOffset,
  }) {
    _progressDiagnostics.log(
      'visible_flush',
      fields: <String, Object?>{
        'reason': reason,
        'novelId': snapshot.novelId,
        'episodeId': snapshot.episodeId,
        'flowMode': snapshot.flowMode.name,
        'scrollOffset': snapshot.scrollOffset.toStringAsFixed(2),
        'progressPercent': snapshot.progressPercent.toStringAsFixed(4),
        'pageIndex': snapshot.pageIndex,
        'pageCount': snapshot.pageCount,
        'maxScrollExtent': maxScrollExtent?.toStringAsFixed(2),
        'hasClients': hasClients,
        'hasRestoredOffset': hasRestoredOffset,
      },
    );
  }

  Future<void> _fallbackToVertical(NovelReaderController controller) async {
    final current = ref.read(novelReaderControllerProvider(_args)).value;
    if (current == null ||
        current.preferences.flowMode == NovelReaderFlowMode.vertical) {
      return;
    }
    final next = current.persistedPreferences.copyWith(
      flowMode: NovelReaderFlowMode.vertical,
    );
    controller.previewPreferences(next);
    try {
      await controller.commitPreferences(next);
    } catch (_) {
      controller.revertPreferencePreview();
      if (mounted) {
        _showReaderSnackBar(
          AppLocalizations.of(context).novelReturnToScrollFailed,
        );
      }
    }
  }

  Future<T> _runWithReaderSemanticsSuspended<T>(
    Future<T> Function() action,
  ) async {
    _suspendReaderSemantics();
    try {
      return await action();
    } finally {
      _resumeReaderSemantics();
    }
  }

  void _suspendReaderSemantics() {
    if (!mounted) {
      _readerSemanticsSuspendCount += 1;
      return;
    }
    setState(() {
      _readerSemanticsSuspendCount += 1;
    });
  }

  void _resumeReaderSemantics() {
    if (_readerSemanticsSuspendCount == 0) {
      return;
    }
    if (!mounted) {
      _readerSemanticsSuspendCount -= 1;
      return;
    }
    setState(() {
      _readerSemanticsSuspendCount -= 1;
    });
  }

  Future<void> _showChapterListSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    await _runWithReaderSemanticsSuspended(() async {
      final selected = await showModalBottomSheet<NovelEpisodeItem>(
        context: context,
        builder: (context) => Consumer(
          builder: (context, ref, _) {
            final latest =
                ref.watch(novelReaderControllerProvider(_args)).value ??
                viewState;
            return NovelReaderChapterListSheet(viewState: latest);
          },
        ),
      );
      if (selected == null ||
          selected.episodeId == viewState.currentEpisode.episodeId) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _openDifferentEpisode(
        () => controller.openEpisodeFromCatalog(selected.episodeId),
      );
    });
  }

  Future<void> _showDisplaySettingsSheet(
    NovelReaderViewState viewState,
    NovelReaderController controller,
  ) async {
    _overlayController.hideMenu();
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.5;
    _pendingDisplayPreferences = viewState.preferences;
    _lastPreviewedDisplayPreferences = viewState.preferences;
    _lastPersistedDisplayPreferences = viewState.persistedPreferences;
    _inFlightDisplayPreferences = null;
    await _runWithReaderSemanticsSuspended(() async {
      await showModalBottomSheet<void>(
        context: context,
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        builder: (context) => NovelReaderDisplaySettingsSheet(
          initialPreferences: viewState.preferences,
          onPreferencesChanged: (preferences) =>
              _onDisplayPreferencesChanged(preferences, controller),
        ),
      );
      if (!mounted) {
        return;
      }
      await _flushDisplayPreferenceChanges(controller);
    });
  }

  void _onDisplayPreferencesChanged(
    NovelReaderPreferences preferences,
    NovelReaderController controller,
  ) {
    _pendingDisplayPreferences = preferences;
    _scheduleDisplayPreferencePreview(controller);
    _scheduleDisplayPreferencePersist(controller);
  }

  void _scheduleDisplayPreferencePreview(NovelReaderController controller) {
    if (_displayPreviewThrottle?.isActive == true) {
      return;
    }
    _applyPendingDisplayPreview(controller);
    _displayPreviewThrottle = Timer(const Duration(milliseconds: 90), () {
      _displayPreviewThrottle = null;
      _applyPendingDisplayPreview(controller);
    });
  }

  void _applyPendingDisplayPreview(NovelReaderController controller) {
    final preferences = _pendingDisplayPreferences;
    if (preferences == null ||
        preferences == _lastPreviewedDisplayPreferences) {
      return;
    }
    _lastPreviewedDisplayPreferences = preferences;
    controller.previewPreferences(preferences);
  }

  void _scheduleDisplayPreferencePersist(NovelReaderController controller) {
    _displayPersistDebounce?.cancel();
    _displayPersistDebounce = Timer(const Duration(milliseconds: 520), () {
      _displayPersistDebounce = null;
      unawaited(_persistPendingDisplayPreferences(controller));
    });
  }

  Future<void> _flushDisplayPreferenceChanges(
    NovelReaderController controller,
  ) async {
    _displayPreviewThrottle?.cancel();
    _displayPreviewThrottle = null;
    _displayPersistDebounce?.cancel();
    _displayPersistDebounce = null;
    _applyPendingDisplayPreview(controller);
    await _persistPendingDisplayPreferences(controller);
  }

  Future<void> _persistPendingDisplayPreferences(
    NovelReaderController controller,
  ) async {
    final preferences = _pendingDisplayPreferences;
    if (preferences == null ||
        preferences == _lastPersistedDisplayPreferences ||
        preferences == _inFlightDisplayPreferences) {
      return;
    }
    _inFlightDisplayPreferences = preferences;
    final serial = ++_displayPersistSerial;
    try {
      await controller.commitPreferences(preferences);
      if (serial == _displayPersistSerial) {
        _lastPersistedDisplayPreferences = preferences;
      }
    } catch (_) {
      if (!mounted || serial != _displayPersistSerial) {
        return;
      }
      controller.revertPreferencePreview();
      _showReaderSnackBar(
        AppLocalizations.of(context).novelSaveDisplaySettingsFailed,
      );
    } finally {
      if (_inFlightDisplayPreferences == preferences) {
        _inFlightDisplayPreferences = null;
      }
    }
  }

  Future<void> _toggleEpisodeBookmark(NovelReaderViewState viewState) async {
    final controller = ref.read(novelReaderControllerProvider(_args).notifier);
    await controller.toggleCurrentEpisodeBookmark();
    if (!mounted) {
      return;
    }
    final latest = ref.read(novelReaderControllerProvider(_args)).value;
    final isBookmarked =
        latest?.hasCurrentEpisodeBookmark ??
        !viewState.hasCurrentEpisodeBookmark;
    final l10n = AppLocalizations.of(context);
    _showReaderSnackBar(
      isBookmarked ? l10n.novelBookmarkAdded : l10n.novelBookmarkRemoved,
    );
  }

  Future<void> _openSourceThread(NovelReaderViewState viewState) async {
    final tid = (viewState.novel?.sourceTid.trim().isNotEmpty == true)
        ? viewState.novel!.sourceTid
        : viewState.currentEpisode.sourceTid;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ThreadDetailPage(tid: tid, subject: _novelTitle(viewState)),
      ),
    );
  }

  String _imageRefererFor(NovelReaderViewState viewState) {
    final tid = viewState.currentEpisode.sourceTid.trim();
    if (tid.isEmpty) {
      return AppConfig.siteBaseUrl;
    }
    final page = viewState.currentEpisode.sourcePage;
    return Uri.parse(AppConfig.siteBaseUrl)
        .replace(
          path: '/forum.php',
          queryParameters: <String, String>{
            'mod': 'viewthread',
            'tid': tid,
            'mobile': '2',
            if (page != null && page > 1) 'page': page.toString(),
          },
        )
        .toString();
  }

  Future<void> _openFallbackSourceThread() async {
    final viewState = ref.read(novelReaderControllerProvider(_args)).value;
    if (viewState != null) {
      await _openSourceThread(viewState);
      return;
    }
    final tid =
        _sourceTidFromId(widget.initialEpisodeId) ??
        _sourceTidFromId(widget.novelId) ??
        widget.novelId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(tid: tid, subject: widget.novelId),
      ),
    );
  }

  Future<void> _openReaderLink(
    NovelReaderLink link,
    ForumWebViewExternalLauncher externalLauncher,
  ) async {
    final destination = const YamiboForumLinkResolver().resolve(link.url);
    if (destination?.kind == YamiboForumLinkKind.thread ||
        destination?.kind == YamiboForumLinkKind.threadPost) {
      final tid = destination?.tid;
      if (tid != null && tid.trim().isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadDetailPage(tid: tid, subject: link.text),
          ),
        );
        return;
      }
    }
    final tid = link.tid;
    if (tid != null && tid.trim().isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ThreadDetailPage(tid: tid, subject: link.text),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(link.url);
    if (uri == null) {
      return;
    }
    final launched = await externalLauncher.launch(uri);
    if (!mounted || launched) {
      return;
    }
    _showReaderSnackBar(AppLocalizations.of(context).novelLinkOpenFailed);
  }

  void _openHtmlReaderImage(ThreadImageOpenRequest request) {
    if (request.continuousImages.isEmpty) {
      final entry = request.initialEntry;
      if (entry != null) {
        _copyNovelImageUrl(entry.url);
      }
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadImageReaderPage(
          request: request,
          imageHeaderBuilder: ref.read(imageRequestHeaderBuilderProvider),
        ),
      ),
    );
  }

  Future<void> _copyNovelImageUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    _showReaderSnackBar(AppLocalizations.of(context).novelImageLinkCopied);
  }

  void _showReaderSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        ),
      );
  }

  Future<void> _updateWorkFromErrorView() async {
    final didSucceed = await ref
        .read(novelReaderControllerProvider(_args).notifier)
        .updateWork();
    if (!mounted || didSucceed) {
      return;
    }
    _showReaderSnackBar(AppLocalizations.of(context).novelWorkUpdateFailed);
  }

  String _novelTitle(NovelReaderViewState viewState) {
    final title = viewState.novel?.title.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final episodeTitle = viewState.currentEpisode.episodeTitle.trim();
    if (episodeTitle.isNotEmpty) {
      return episodeTitle;
    }
    return NovelTextResolver.workTitle(
      AppLocalizations.of(context),
      '',
      widget.novelId,
    );
  }

  String? _sourceTidFromId(String value) {
    final parts = value.split(':');
    if (parts.length >= 3 && parts.first == 'novel') {
      final tid = parts[2].trim();
      return tid.isEmpty ? null : tid;
    }
    return null;
  }

  double _safeContentMaxWidth(NovelReaderTypography typography) {
    return typography.contentMaxWidth < 160 ? 160 : typography.contentMaxWidth;
  }
}

class NovelReaderChapterListSheet extends StatefulWidget {
  const NovelReaderChapterListSheet({super.key, required this.viewState});

  final NovelReaderViewState viewState;

  static const double itemExtent = 72;

  @override
  State<NovelReaderChapterListSheet> createState() =>
      _NovelReaderChapterListSheetState();
}

class _NovelReaderChapterListSheetState
    extends State<NovelReaderChapterListSheet> {
  late final ScrollController _scrollController;
  String _keyword = '';

  NovelReaderViewState get viewState => widget.viewState;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filteredEpisodes = _filteredEpisodes();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          key: const Key('novel-reader-chapter-list-sheet'),
          children: [
            ReaderSheetTitle(title: l10n.novelCatalog),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('novel-reader-chapter-search-field'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.novelSearchChapters,
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _keyword = value.trim();
                  });
                },
              ),
            ),
            Expanded(
              child: filteredEpisodes.isEmpty
                  ? Center(
                      key: const Key('novel-reader-chapter-search-empty'),
                      child: Text(l10n.novelNoMatchingChapters),
                    )
                  : ListView.builder(
                      controller: _keyword.isEmpty ? _scrollController : null,
                      itemExtent: NovelReaderChapterListSheet.itemExtent,
                      itemCount: filteredEpisodes.length,
                      itemBuilder: (context, index) {
                        return _ChapterListTile(
                          episode: filteredEpisodes[index],
                          currentEpisodeId: viewState.currentEpisode.episodeId,
                          readingProgressEpisodeId:
                              viewState.readingProgress?.episodeId,
                          bookmarkEpisodeIds: viewState.bookmarkEpisodeIds,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToCurrentEpisode() {
    if (!mounted || _keyword.isNotEmpty || !_scrollController.hasClients) {
      return;
    }
    final offset = _currentEpisodeInitialOffset();
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      return;
    }
    _scrollController.jumpTo(offset.clamp(0.0, max).toDouble());
  }

  double _currentEpisodeInitialOffset() {
    final currentIndex = viewState.currentEpisodeIndex;
    if (currentIndex <= 0) {
      return 0;
    }
    final anchoredIndex = currentIndex <= 2 ? 0 : currentIndex - 2;
    return anchoredIndex * NovelReaderChapterListSheet.itemExtent;
  }

  List<NovelEpisodeItem> _filteredEpisodes() {
    final keyword = _keyword.toLowerCase();
    if (keyword.isEmpty) {
      return viewState.episodes;
    }
    return viewState.episodes
        .where((episode) {
          return episode.episodeTitle.toLowerCase().contains(keyword) ||
              (episode.datelineText ?? '').toLowerCase().contains(keyword) ||
              (episode.sourcePid ?? '').toLowerCase().contains(keyword);
        })
        .toList(growable: false);
  }
}

class _ChapterListTile extends StatelessWidget {
  const _ChapterListTile({
    required this.episode,
    required this.currentEpisodeId,
    required this.readingProgressEpisodeId,
    required this.bookmarkEpisodeIds,
  });

  final NovelEpisodeItem episode;
  final String currentEpisodeId;
  final String? readingProgressEpisodeId;
  final Set<String> bookmarkEpisodeIds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isCurrent = episode.episodeId == currentEpisodeId;
    final isLastRead =
        !isCurrent && episode.episodeId == readingProgressEpisodeId;
    final isBookmarked = bookmarkEpisodeIds.contains(episode.episodeId);
    return ListTile(
      key: Key('novel-reader-chapter-${episode.episodeId}'),
      selected: isCurrent,
      leading: Icon(
        isBookmarked
            ? Icons.bookmark
            : isCurrent
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(
        NovelTextResolver.chapterTitle(
          l10n,
          episode.episodeTitle,
          episode.sourceTid,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: episode.datelineText == null
          ? null
          : Text(
              episode.datelineText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Wrap(
        spacing: 6,
        children: [
          if (isBookmarked)
            Text(
              l10n.novelBookmark,
              key: Key('novel-reader-chapter-bookmark-${episode.episodeId}'),
            ),
          if (isCurrent)
            Text(l10n.novelCurrent)
          else if (isLastRead)
            Text(l10n.novelLastRead),
        ],
      ),
      onTap: () => Navigator.of(context).pop(episode),
    );
  }
}

class NovelReaderNextChapterTransition extends StatelessWidget {
  const NovelReaderNextChapterTransition({
    super.key,
    required this.nextEpisode,
    required this.onPressed,
  });

  final NovelEpisodeItem nextEpisode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('novel-reader-next-chapter-transition'),
      child: OutlinedButton.icon(
        key: const Key('novel-reader-next-chapter-button'),
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward),
        label: Text(
          l10n.novelNextChapter(
            NovelTextResolver.chapterTitle(
              l10n,
              nextEpisode.episodeTitle,
              nextEpisode.sourceTid,
            ),
          ),
        ),
      ),
    );
  }
}

class NovelReaderErrorView extends StatelessWidget {
  const NovelReaderErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onUpdateWork,
    required this.onOpenThread,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onUpdateWork;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          key: const Key('novel-reader-error-view'),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 42),
                  const SizedBox(height: 16),
                  Text(
                    l10n.novelChapterUnavailable,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    NovelTextResolver.readerFailure(l10n, error),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const Key('novel-reader-error-retry'),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.commonRetry),
                      ),
                      OutlinedButton.icon(
                        key: const Key('novel-reader-error-update-work'),
                        onPressed: onUpdateWork,
                        icon: const Icon(Icons.sync),
                        label: Text(l10n.novelUpdateWork),
                      ),
                      OutlinedButton.icon(
                        key: const Key('novel-reader-error-open-thread'),
                        onPressed: onOpenThread,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.novelOpenSourceThread),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
