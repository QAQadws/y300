import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_anchor_navigation_request.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_diagnostics.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_html_image_reader_bridge.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_restore_policy.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

typedef NovelReaderPaginationCoordinatorBuilder =
    NovelReaderPaginationCoordinator Function({
      required BuildContext context,
      required ForumHtmlThemeContext theme,
      required ForumHtmlReaderPreferences preferences,
      required String sourceId,
      required String? threadId,
      required String? imageCacheOwnerId,
      required ImageRequestHeaderBuilder? imageHeaderBuilder,
    });

class NovelReaderHtmlPagedSurface extends StatefulWidget {
  const NovelReaderHtmlPagedSurface({
    super.key,
    required this.rawHtml,
    required this.episode,
    required this.preferences,
    required this.typography,
    required this.theme,
    required this.imageReferer,
    required this.progressSnapshot,
    this.semanticDocument,
    this.navigationRequest,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
    this.onFallbackToVertical,
    this.onPositionChanged,
    this.onNavigationUnavailable,
    this.preferencesAdapter = const NovelHtmlReaderPreferencesAdapter(),
    this.preparer = const NovelHtmlChapterRenderPreparer(),
    this.preparationService,
    this.imageReaderBridge = const NovelHtmlImageReaderBridge(),
    this.coordinatorBuilder,
    this.restorePolicy = const NovelReaderPaginationRestorePolicy(),
    this.paginationCache,
    this.paginationMeasureCache,
    this.preparedChapterCache,
    this.diagnosticsSink = const NovelReaderNoopPaginationDiagnosticsSink(),
    this.chromeInsets = const ReaderChromeInsets.zero(),
  });

  final String rawHtml;
  final NovelEpisodeItem episode;
  final NovelReaderPreferences preferences;
  final NovelReaderTypography typography;
  final ForumHtmlThemeContext theme;
  final String imageReferer;
  final NovelReaderProgressSnapshot progressSnapshot;
  final NovelReaderDocument? semanticDocument;
  final NovelReaderAnchorNavigationRequest? navigationRequest;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final VoidCallback? onFallbackToVertical;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final ValueChanged<NovelReaderAnchorNavigationRequest>?
  onNavigationUnavailable;
  final NovelHtmlReaderPreferencesAdapter preferencesAdapter;
  final NovelHtmlChapterPreparer preparer;
  final NovelReaderHtmlPreparationService? preparationService;
  final NovelHtmlImageReaderBridge imageReaderBridge;
  final NovelReaderPaginationCoordinatorBuilder? coordinatorBuilder;
  final NovelReaderPaginationRestorePolicy restorePolicy;
  final NovelReaderPaginationCache? paginationCache;
  final NovelReaderPaginationMeasureCache? paginationMeasureCache;
  final NovelReaderPreparedChapterCache? preparedChapterCache;
  final NovelReaderPaginationDiagnosticsSink diagnosticsSink;
  final ReaderChromeInsets chromeInsets;

  @override
  State<NovelReaderHtmlPagedSurface> createState() =>
      _NovelReaderHtmlPagedSurfaceState();
}

class _NovelReaderHtmlPagedSurfaceState
    extends State<NovelReaderHtmlPagedSurface> {
  Future<NovelReaderPreparedChapter>? _prepareFuture;
  Object? _prepareSignature;
  NovelReaderPaginationCoordinator? _coordinator;
  Object? _coordinatorSignature;
  Stream<NovelReaderPaginationProgress>? _planStream;
  NovelReaderPaginationKey? _planKey;
  NovelReaderPaginationCache? _ownedCache;
  NovelReaderPaginationMeasureCache? _ownedMeasureCache;
  NovelReaderPreparedChapterCache? _ownedPreparedCache;
  Duration _preparationDuration = Duration.zero;
  int _layoutGeneration = 0;
  String? _lastUnavailableNavigationKey;
  String? _recordedDiagnosticsKey;
  Stopwatch? _layoutStopwatch;
  bool _layoutCacheHit = false;

  @override
  void initState() {
    super.initState();
    _ensurePreparationFuture();
  }

  @override
  void didUpdateWidget(covariant NovelReaderHtmlPagedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensurePreparationFuture();
  }

  @override
  void dispose() {
    _coordinator?.cancelPending();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final htmlPreferences = widget.preferencesAdapter.map(widget.preferences);
    return DefaultTextStyle.merge(
      style: widget.typography.body,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pagePadding = widget.preferences.pagePadding
              .clamp(0.0, 96.0)
              .toDouble();
          final topChromeInset = widget.chromeInsets.topInset;
          final bottomChromeInset = widget.chromeInsets.bottomInset;
          final availableWidth = constraints.maxWidth - pagePadding * 2;
          final availableHeight =
              constraints.maxHeight -
              pagePadding * 2 -
              topChromeInset -
              bottomChromeInset;
          final contentMaxWidth = widget.typography.contentMaxWidth < 160
              ? 160
              : widget.typography.contentMaxWidth;
          final pageWidth = math
              .min(availableWidth, contentMaxWidth)
              .toDouble();
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              pageWidth <= 0 ||
              availableHeight <= 0) {
            return const _NovelReaderPaginationStateView(
              key: Key('novel-reader-paged-invalid-viewport'),
              icon: Icons.crop_free,
              message: '当前窗口无法生成分页布局',
            );
          }

          return FutureBuilder<NovelReaderPreparedChapter>(
            key: ValueKey<Object?>(_prepareSignature),
            future: _prepareFuture,
            builder: (context, snapshot) {
              final prepared = snapshot.data;
              if (prepared == null) {
                if (snapshot.hasError) {
                  return _NovelReaderPaginationFailureView(
                    error: snapshot.error!,
                    onRetry: _retryPreparation,
                    onFallbackToVertical: widget.onFallbackToVertical,
                  );
                }
                return const _NovelReaderPaginationStateView(
                  key: Key('novel-reader-paged-preparing'),
                  icon: Icons.menu_book_outlined,
                  message: '正在准备分页正文',
                  showProgress: true,
                );
              }

              final key = NovelReaderPaginationKey(
                episodeId: prepared.episodeId,
                contentHash: prepared.contentHash,
                viewportWidthPx: NovelReaderPaginationKey.logicalPixels(
                  pageWidth,
                ),
                viewportHeightPx: NovelReaderPaginationKey.logicalPixels(
                  availableHeight,
                ),
                typographySignature: _typographySignature(
                  widget.preferences,
                  widget.typography,
                  htmlPreferences,
                  MediaQuery.textScalerOf(context),
                ),
                themeSignature: widget.theme.signature,
                imageDimensionRevision: prepared.imageDimensionRevision,
                rendererRevision: 3,
                topChromeInsetPx: NovelReaderPaginationKey.logicalPixels(
                  topChromeInset,
                ),
                bottomChromeInsetPx: NovelReaderPaginationKey.logicalPixels(
                  bottomChromeInset,
                ),
              );
              final planStream = _ensurePlanStream(
                context: context,
                prepared: prepared,
                key: key,
                htmlPreferences: htmlPreferences,
              );
              return StreamBuilder<NovelReaderPaginationProgress>(
                key: ValueKey<NovelReaderPaginationKey>(key),
                stream: planStream,
                builder: (context, planSnapshot) {
                  final progress = planSnapshot.data;
                  final plan = progress?.plan;
                  if (plan == null) {
                    if (planSnapshot.hasError) {
                      return _NovelReaderPaginationFailureView(
                        error: planSnapshot.error!,
                        onRetry: _retryPlan,
                        onFallbackToVertical: widget.onFallbackToVertical,
                      );
                    }
                    return const _NovelReaderPaginationStateView(
                      key: Key('novel-reader-paged-layout-loading'),
                      icon: Icons.view_agenda_outlined,
                      message: '正在计算分页布局',
                      showProgress: true,
                    );
                  }
                  if (plan.pages.isEmpty) {
                    if (progress?.isComplete != true) {
                      return const _NovelReaderPaginationStateView(
                        key: Key('novel-reader-paged-layout-loading'),
                        icon: Icons.view_agenda_outlined,
                        message: '正在计算分页布局',
                        showProgress: true,
                      );
                    }
                    return const _NovelReaderPaginationStateView(
                      key: Key('novel-reader-paged-empty'),
                      icon: Icons.article_outlined,
                      message: '本章没有可显示的正文',
                    );
                  }
                  final requestedPage = _requestedPageFor(plan);
                  if (progress?.isComplete == true) {
                    _scheduleDiagnostics(
                      plan: plan,
                      prepared: prepared,
                      key: key,
                    );
                    _scheduleUnavailableNavigationIfNeeded(
                      plan: plan,
                      requestedPage: requestedPage,
                    );
                  }
                  return Padding(
                    key: const Key('novel-reader-paged-surface'),
                    padding: EdgeInsets.fromLTRB(
                      pagePadding,
                      pagePadding + topChromeInset,
                      pagePadding,
                      pagePadding + bottomChromeInset,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: pageWidth,
                        height: availableHeight,
                        child: _NovelReaderPagedPageView(
                          key: ValueKey<String>(plan.key.cacheIdentity),
                          plan: plan,
                          isPageCountFinal: progress?.isComplete == true,
                          initialPage:
                              requestedPage ??
                              widget.restorePolicy.resolveInitialPage(
                                plan: plan,
                                snapshot: widget.progressSnapshot,
                              ),
                          navigationRequest: widget.navigationRequest,
                          targetPage: requestedPage,
                          reverse:
                              widget.preferences.flowMode ==
                              NovelReaderFlowMode.pagedRtl,
                          showProgressIndicator:
                              widget.preferences.showProgressIndicator,
                          theme: widget.theme,
                          htmlPreferences: htmlPreferences,
                          typography: widget.typography,
                          renderDocument: prepared.renderDocument,
                          episode: widget.episode,
                          imageReferer: widget.imageReferer,
                          imageHeaderBuilder: widget.imageHeaderBuilder,
                          onLinkTap: widget.onLinkTap,
                          onOpenImage: widget.onOpenImage,
                          onImageFallback: widget.onImageFallback,
                          imageReaderBridge: widget.imageReaderBridge,
                          onPositionChanged: (position) {
                            if (mounted && _planKey == plan.key) {
                              widget.onPositionChanged?.call(position);
                            }
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Stream<NovelReaderPaginationProgress> _ensurePlanStream({
    required BuildContext context,
    required NovelReaderPreparedChapter prepared,
    required NovelReaderPaginationKey key,
    required ForumHtmlReaderPreferences htmlPreferences,
  }) {
    if (_planKey == key && _planStream != null) {
      return _planStream!;
    }
    if (_planKey != null && _planKey != key) {
      _coordinator?.cancelPending();
    }
    final coordinatorSignature = (
      theme: widget.theme.signature,
      preferences: htmlPreferences,
      sourceId: widget.episode.episodeId,
      threadId: widget.episode.sourceTid,
      imageOwner: widget.episode.sourceTid,
      headerBuilder: widget.imageHeaderBuilder,
      textScale: MediaQuery.textScalerOf(context).scale(1000).round(),
      builder: widget.coordinatorBuilder,
    );
    if (_coordinator == null || _coordinatorSignature != coordinatorSignature) {
      _coordinator?.cancelPending();
      _coordinatorSignature = coordinatorSignature;
      _coordinator =
          widget.coordinatorBuilder?.call(
            context: context,
            theme: widget.theme,
            preferences: htmlPreferences,
            sourceId: widget.episode.episodeId,
            threadId: widget.episode.sourceTid,
            imageCacheOwnerId: widget.episode.sourceTid,
            imageHeaderBuilder: widget.imageHeaderBuilder,
          ) ??
          _defaultCoordinator(
            context: context,
            htmlPreferences: htmlPreferences,
          );
    }
    _planKey = key;
    _layoutGeneration += 1;
    _layoutCacheHit = _coordinator!.isCached(key);
    _layoutStopwatch = Stopwatch()..start();
    _recordedDiagnosticsKey = null;
    _planStream = _coordinator!.paginateIncrementally(
      chapter: prepared,
      key: key,
    );
    return _planStream!;
  }

  void _scheduleDiagnostics({
    required NovelReaderPaginationPlan plan,
    required NovelReaderPreparedChapter prepared,
    required NovelReaderPaginationKey key,
  }) {
    final diagnosticsKey = key.cacheIdentity;
    if (_recordedDiagnosticsKey == diagnosticsKey) {
      return;
    }
    _recordedDiagnosticsKey = diagnosticsKey;
    final stopwatch = _layoutStopwatch;
    if (stopwatch?.isRunning == true) {
      stopwatch!.stop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _planKey != key) {
        return;
      }
      widget.diagnosticsSink.record(
        NovelReaderPaginationDiagnostics(
          episodeId: plan.episodeId,
          paginationKey: key.layoutFingerprint,
          pageCount: plan.pageCount,
          layoutDuration: stopwatch?.elapsed ?? Duration.zero,
          reflowCount: _layoutGeneration - 1,
          unknownImageDimensionCount: prepared.renderDocument.sequence.entries
              .where(
                (entry) => entry.htmlWidth == null || entry.htmlHeight == null,
              )
              .length,
          overflowPageCount: plan.pages
              .where((page) => page.hasOverflow)
              .length,
          cacheHit: _layoutCacheHit,
          flowUnitCount: prepared.flowUnits.length,
          atomCount: plan.atomCount,
          measurementCount: plan.measurementCount,
          measurementCacheHitCount: plan.measurementCacheHitCount,
          measurementDuration: plan.measurementDuration,
          preparationDuration: _preparationDuration,
          atomizationDuration: plan.atomizationDuration,
          measureSessionCreateDuration: plan.measureSessionCreateDuration,
          classificationDuration: plan.classificationDuration,
          frameWaitCount: plan.frameWaitCount,
          domSliceCount: plan.domSliceCount,
          readableImageCount: plan.readableImageCount,
          textFastPathCount: plan.textFastPathCount,
          rendererValidationCount: plan.rendererValidationCount,
          rendererValidationMismatchCount: plan.rendererValidationMismatchCount,
          textLayoutCount: plan.textLayoutCount,
          complexBlockCount: plan.complexBlockCount,
          safeTextFallbackCount: plan.safeTextFallbackCount,
          availableHeight: key.viewportHeightPx.toDouble(),
          averageTextPageFullness: plan.averageTextPageFullness,
          lowFullnessPageCount: plan.lowFullnessPageCount,
          gapReasonCounts: plan.gapReasonCounts,
          atomKindCounts: plan.atomKindCounts,
          routeCounts: plan.routeCounts,
          routeReasonCounts: plan.routeReasonCounts,
          measurementSamples: plan.measurementSamples,
        ),
      );
    });
  }

  NovelReaderPaginationCoordinator _defaultCoordinator({
    required BuildContext context,
    required ForumHtmlReaderPreferences htmlPreferences,
  }) {
    final measureAdapter = NovelReaderHtmlPaginationMeasureAdapter(
      hostContext: context,
      theme: widget.theme,
      preferences: htmlPreferences,
      sourceId: widget.episode.episodeId,
      threadId: widget.episode.sourceTid,
      imageCacheOwnerId: widget.episode.sourceTid,
      imageHeaderBuilder: widget.imageHeaderBuilder,
    );
    return DefaultNovelReaderPaginationCoordinator(
      pageBreaker: DefaultNovelReaderHybridPaginationPlanner(
        measureAdapter: measureAdapter,
        preferences: htmlPreferences,
        theme: widget.theme,
        baseStyle: widget.typography.body,
        textAlign: widget.typography.textAlign,
        textScaler: MediaQuery.textScalerOf(context),
        measureCache:
            widget.paginationMeasureCache ??
            (_ownedMeasureCache ??= NovelReaderPaginationMeasureCache()),
      ),
      cache:
          widget.paginationCache ??
          (_ownedCache ??= NovelReaderPaginationCache()),
    );
  }

  void _ensurePreparationFuture() {
    final htmlPreferences = widget.preferencesAdapter.map(widget.preferences);
    final signature = (
      rawHtml: widget.rawHtml,
      episodeId: widget.episode.episodeId,
      sourceTid: widget.episode.sourceTid,
      semanticDocumentHash: widget.semanticDocument?.rawHtmlHash,
      preferences: htmlPreferences,
      themeSignature: widget.theme.signature,
      preparationService: widget.preparationService,
      preparer: widget.preparer,
    );
    if (_prepareSignature == signature) {
      return;
    }
    _prepareSignature = signature;
    _coordinator?.cancelPending();
    final preparationService = NovelReaderCachingHtmlPreparationService(
      delegate:
          widget.preparationService ??
          DefaultNovelReaderHtmlPreparationService(preparer: widget.preparer),
      cache:
          widget.preparedChapterCache ??
          (_ownedPreparedCache ??= NovelReaderPreparedChapterCache()),
    );
    final stopwatch = Stopwatch()..start();
    final future = preparationService.prepare(
      rawHtml: widget.rawHtml,
      episode: widget.episode,
      preferences: htmlPreferences,
      theme: widget.theme,
      sourceId: widget.episode.episodeId,
      threadId: widget.episode.sourceTid,
      imageCacheOwnerId: widget.episode.sourceTid,
      semanticDocument: widget.semanticDocument,
    );
    _prepareFuture = future;
    unawaited(
      future.then<void>(
        (_) {
          stopwatch.stop();
          if (identical(_prepareFuture, future)) {
            _preparationDuration = stopwatch.elapsed;
          }
        },
        onError: (Object error, StackTrace stack) {
          stopwatch.stop();
        },
      ),
    );
    _coordinator = null;
    _coordinatorSignature = null;
    _planStream = null;
    _planKey = null;
  }

  String _typographySignature(
    NovelReaderPreferences preferences,
    NovelReaderTypography typography,
    ForumHtmlReaderPreferences htmlPreferences,
    TextScaler textScaler,
  ) {
    return jsonEncode(<Object?>[
      preferences.fontSize,
      preferences.lineHeight,
      preferences.paragraphSpacing,
      preferences.pagePadding,
      preferences.fontFamily,
      preferences.contentMaxWidth,
      preferences.firstLineIndent,
      preferences.fontWeight,
      preferences.textAlign.name,
      htmlPreferences.typography.fontScale,
      htmlPreferences.typography.lineHeightScale,
      htmlPreferences.typography.paragraphSpacing,
      typography.textAlign.index,
      textScaler.scale(1000).round(),
    ]);
  }

  void _retryPreparation() {
    if (!mounted) {
      return;
    }
    _coordinator?.cancelPending();
    setState(() {
      _prepareFuture = null;
      _prepareSignature = null;
      _planStream = null;
      _planKey = null;
    });
  }

  void _retryPlan() {
    if (!mounted) {
      return;
    }
    _coordinator?.clear();
    setState(() {
      _planStream = null;
      _planKey = null;
    });
  }

  int? _requestedPageFor(NovelReaderPaginationPlan plan) {
    final request = widget.navigationRequest;
    if (request == null || request.anchor.episodeId != plan.episodeId) {
      return null;
    }
    return plan.pageIndexForAnchor(request.anchor);
  }

  void _scheduleUnavailableNavigationIfNeeded({
    required NovelReaderPaginationPlan plan,
    required int? requestedPage,
  }) {
    final request = widget.navigationRequest;
    if (request == null ||
        request.anchor.episodeId != plan.episodeId ||
        requestedPage != null) {
      return;
    }
    final requestKey = '${request.requestId}|${plan.key.layoutFingerprint}';
    if (_lastUnavailableNavigationKey == requestKey) {
      return;
    }
    _lastUnavailableNavigationKey = requestKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _planKey == plan.key) {
        widget.onNavigationUnavailable?.call(request);
      }
    });
  }
}

class _NovelReaderPagedPageView extends StatefulWidget {
  const _NovelReaderPagedPageView({
    super.key,
    required this.plan,
    required this.isPageCountFinal,
    required this.initialPage,
    this.navigationRequest,
    this.targetPage,
    required this.reverse,
    required this.showProgressIndicator,
    required this.theme,
    required this.htmlPreferences,
    required this.typography,
    required this.renderDocument,
    required this.episode,
    required this.imageReferer,
    required this.imageReaderBridge,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
    this.onPositionChanged,
  });

  final NovelReaderPaginationPlan plan;
  final bool isPageCountFinal;
  final int initialPage;
  final NovelReaderAnchorNavigationRequest? navigationRequest;
  final int? targetPage;
  final bool reverse;
  final bool showProgressIndicator;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences htmlPreferences;
  final NovelReaderTypography typography;
  final ForumHtmlPreparedRenderDocument renderDocument;
  final NovelEpisodeItem episode;
  final String imageReferer;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final NovelHtmlImageReaderBridge imageReaderBridge;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;

  @override
  State<_NovelReaderPagedPageView> createState() =>
      _NovelReaderPagedPageViewState();
}

class _NovelReaderPagedPageViewState extends State<_NovelReaderPagedPageView> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _reportedInitialPage = false;
  bool _hasUserNavigated = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(
      initialPage: widget.initialPage,
      keepPage: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_reportedInitialPage && widget.plan.pageCount > 0) {
        _reportedInitialPage = true;
        _emitPosition(widget.initialPage);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _NovelReaderPagedPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isPageCountFinal && widget.isPageCountFinal) {
      final restoredPage = widget.initialPage
          .clamp(0, math.max(0, widget.plan.pageCount - 1))
          .toInt();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (!_hasUserNavigated && restoredPage != _currentPage) {
          _pageController.jumpToPage(restoredPage);
          setState(() {
            _currentPage = restoredPage;
          });
        }
        _emitPosition(_currentPage);
      });
    }
    final oldRequestId = oldWidget.navigationRequest?.requestId;
    final newRequestId = widget.navigationRequest?.requestId;
    if (oldRequestId == newRequestId || widget.targetPage == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.targetPage == null) {
        return;
      }
      _pageController.jumpToPage(widget.targetPage!);
      _emitPosition(widget.targetPage!);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.plan.pageCount;
    final totalPageLabel = widget.isPageCountFinal ? '$pageCount 页' : '计算中';
    return Semantics(
      key: const Key('novel-reader-paged-semantics'),
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label:
          '${widget.episode.episodeTitle}，第 ${_currentPage + 1} 页，共 $totalPageLabel',
      value: '第 ${_currentPage + 1} 页，共 $totalPageLabel',
      increasedValue: _currentPage + 1 < pageCount
          ? '下一页，第 ${_currentPage + 2} 页'
          : null,
      decreasedValue: _currentPage > 0 ? '上一页，第 $_currentPage 页' : null,
      onIncrease: _currentPage + 1 < pageCount
          ? () => _jumpToPage(_currentPage + 1)
          : null,
      onDecrease: _currentPage > 0 ? () => _jumpToPage(_currentPage - 1) : null,
      child: Stack(
        key: const Key('novel-reader-paged-page-session'),
        fit: StackFit.expand,
        children: [
          PageView.builder(
            key: const Key('novel-reader-paged-page-view'),
            controller: _pageController,
            reverse: widget.reverse,
            allowImplicitScrolling: false,
            itemCount: pageCount,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final page = widget.plan.pages[index];
              return _NovelReaderPagedPage(
                key: ValueKey<String>('novel-reader-paged-page-${page.index}'),
                page: page,
                plan: widget.plan,
                theme: widget.theme,
                htmlPreferences: widget.htmlPreferences,
                typography: widget.typography,
                renderDocument: widget.renderDocument,
                episode: widget.episode,
                imageReferer: widget.imageReferer,
                imageHeaderBuilder: widget.imageHeaderBuilder,
                onLinkTap: widget.onLinkTap,
                onOpenImage: widget.onOpenImage,
                onImageFallback: widget.onImageFallback,
                imageReaderBridge: widget.imageReaderBridge,
              );
            },
          ),
          if (widget.showProgressIndicator)
            Positioned(
              key: const Key('novel-reader-page-indicator'),
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.78),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    '${_currentPage + 1} / ${widget.isPageCountFinal ? pageCount : '计算中'}',
                    key: const Key('novel-reader-page-indicator-text'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _jumpToPage(int index) {
    if (!mounted || index < 0 || index >= widget.plan.pageCount) {
      return;
    }
    _pageController.jumpToPage(index);
    _hasUserNavigated = true;
    if (_currentPage != index) {
      setState(() {
        _currentPage = index;
      });
    }
    _emitPosition(index);
  }

  void _onPageChanged(int index) {
    if (!mounted || index < 0 || index >= widget.plan.pageCount) {
      return;
    }
    if (_reportedInitialPage && index != _currentPage) {
      _hasUserNavigated = true;
    }
    setState(() {
      _currentPage = index;
    });
    _emitPosition(index);
  }

  void _emitPosition(int index) {
    if (!mounted || index < 0 || index >= widget.plan.pageCount) {
      return;
    }
    final page = widget.plan.pageAt(index);
    if (page == null) {
      return;
    }
    widget.onPositionChanged?.call(
      NovelReaderPaginationPosition(
        episodeId: widget.plan.episodeId,
        paginationKey: widget.plan.key.layoutFingerprint,
        pageIndex: index,
        pageCount: widget.plan.pageCount,
        isPageCountFinal: widget.isPageCountFinal,
        anchor: page.startAnchor.copyWith(pageIndex: index),
      ),
    );
  }
}

class _NovelReaderPagedPage extends StatelessWidget {
  const _NovelReaderPagedPage({
    super.key,
    required this.page,
    required this.plan,
    required this.theme,
    required this.htmlPreferences,
    required this.typography,
    required this.renderDocument,
    required this.episode,
    required this.imageReferer,
    required this.imageReaderBridge,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
  });

  final NovelReaderPageFragment page;
  final NovelReaderPaginationPlan plan;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences htmlPreferences;
  final NovelReaderTypography typography;
  final ForumHtmlPreparedRenderDocument renderDocument;
  final NovelEpisodeItem episode;
  final String imageReferer;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final NovelHtmlImageReaderBridge imageReaderBridge;

  @override
  Widget build(BuildContext context) {
    final preparedDocument = renderDocument.copyWith(preparedHtml: page.html);
    Widget child = ForumHtmlWidgetPostRenderer(
      key: ValueKey<int>(page.index),
      html: page.html,
      theme: theme,
      preparedDocument: preparedDocument,
      preferences: htmlPreferences,
      sourceId: episode.episodeId,
      threadId: episode.sourceTid,
      imageHeaderBuilder: imageHeaderBuilder,
      imageCacheOwnerId: episode.sourceTid,
      callbacks: ForumHtmlRenderCallbacks(
        onTapUrl: (url) {
          onLinkTap?.call(NovelReaderLink(url: url, text: url));
          return true;
        },
        onTapImage: (request) => _handleImageTap(
          request: request,
          sequence: preparedDocument.sequence,
        ),
      ),
    );
    if (page.requiresInnerScroll) {
      child = SingleChildScrollView(
        key: ValueKey<int>(page.index),
        child: child,
      );
    }
    return Semantics(
      container: true,
      label: '第 ${page.index + 1} 页，共 ${plan.pageCount} 页',
      child: child,
    );
  }

  void _handleImageTap({
    required ForumHtmlImageRequest request,
    required ForumHtmlReadableImageSequence sequence,
  }) {
    final openRequest = imageReaderBridge.buildOpenRequest(
      threadId: episode.sourceTid,
      episodeId: episode.episodeId,
      postNumber: episode.orderIndex + 1,
      imageReferer: imageReferer,
      sequence: sequence,
      imageRequest: request,
    );
    if (openRequest != null) {
      onOpenImage?.call(openRequest);
      return;
    }
    if (!request.isSticker) {
      onImageFallback?.call(request);
    }
  }
}

class _NovelReaderPaginationStateView extends StatelessWidget {
  const _NovelReaderPaginationStateView({
    super.key,
    required this.icon,
    required this.message,
    this.showProgress = false,
  });

  final IconData icon;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        key: const Key('novel-reader-pagination-state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 12),
          Text(message),
          if (showProgress) ...[
            const SizedBox(height: 12),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _NovelReaderPaginationFailureView extends StatelessWidget {
  const _NovelReaderPaginationFailureView({
    required this.error,
    required this.onRetry,
    required this.onFallbackToVertical,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onFallbackToVertical;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        key: const Key('novel-reader-pagination-failure'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_outlined, size: 34),
          const SizedBox(height: 12),
          const Text('分页布局失败'),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('novel-reader-pagination-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              if (onFallbackToVertical != null)
                FilledButton.icon(
                  key: const Key('novel-reader-pagination-fallback'),
                  onPressed: onFallbackToVertical,
                  icon: const Icon(Icons.view_agenda_outlined),
                  label: const Text('回到滚动'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
