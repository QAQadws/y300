import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_anchor_navigation_request.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_diagnostics.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_paged_indicator_layout.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_html_image_reader_bridge.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_restore_policy.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/l10n/app_localizations.dart';

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
    this.pageSeekRequest,
    this.chapterEntryRequest,
    this.onChapterEntryApplied,
    this.previousChapterTitle,
    this.nextChapterTitle,
    this.imageHeaderBuilder,
    this.onLinkTap,
    this.onOpenImage,
    this.onImageFallback,
    this.onFallbackToVertical,
    this.onPositionChanged,
    this.onContentReady,
    this.onContentTerminal,
    this.onNavigationUnavailable,
    this.onTurnToAdjacentChapter,
    this.chapterTurnPolicy = const NovelReaderChapterTurnPolicy(),
    this.preferencesAdapter = const NovelHtmlReaderPreferencesAdapter(),
    this.preparer = const NovelHtmlChapterRenderPreparer(),
    this.preparationService,
    this.imageReaderBridge = const NovelHtmlImageReaderBridge(),
    this.coordinatorBuilder,
    this.restorePolicy = const NovelReaderPaginationRestorePolicy(),
    this.paginationCache,
    this.paginationMeasureCache,
    this.paginationBoundaryCache,
    this.preparedChapterCache,
    this.diagnosticsSink = const NovelReaderNoopPaginationDiagnosticsSink(),
    this.performancePolicy = const NovelReaderPaginationPerformancePolicy(),
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
  final NovelReaderPageSeekRequest? pageSeekRequest;
  final NovelReaderChapterEntryRequest? chapterEntryRequest;

  /// Fired once [chapterEntryRequest] has actually been resolved into a page and
  /// handed to the page view. The owner must retire the request in response:
  /// while it is still armed the surface treats a chapter turn as in flight, and
  /// a request that is never retired latches the gesture off for good.
  final ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryApplied;

  /// Neighbour titles are passed in as plain labels so the surface never has to
  /// know about the episode list; a null title simply disables that direction.
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<NovelReaderLink>? onLinkTap;
  final void Function(ThreadImageOpenRequest request)? onOpenImage;
  final ValueChanged<ForumHtmlImageRequest>? onImageFallback;
  final VoidCallback? onFallbackToVertical;
  final ValueChanged<NovelReaderPaginationPosition>? onPositionChanged;
  final VoidCallback? onContentReady;
  final VoidCallback? onContentTerminal;
  final ValueChanged<NovelReaderAnchorNavigationRequest>?
  onNavigationUnavailable;

  /// Must report whether the turn was actually accepted. The surface locks the
  /// gesture off while a turn is in flight and relies on the armed entry request
  /// to unlock it, so a rejected turn has to say so — otherwise the lock waits
  /// on a request that is never coming.
  final NovelReaderChapterTurnHandler? onTurnToAdjacentChapter;
  final NovelReaderChapterTurnPolicy chapterTurnPolicy;
  final NovelHtmlReaderPreferencesAdapter preferencesAdapter;
  final NovelHtmlChapterPreparer preparer;
  final NovelReaderHtmlPreparationService? preparationService;
  final NovelHtmlImageReaderBridge imageReaderBridge;
  final NovelReaderPaginationCoordinatorBuilder? coordinatorBuilder;
  final NovelReaderPaginationRestorePolicy restorePolicy;
  final NovelReaderPaginationCache? paginationCache;
  final NovelReaderPaginationMeasureCache? paginationMeasureCache;
  final NovelReaderComplexHtmlBoundaryCache? paginationBoundaryCache;
  final NovelReaderPreparedChapterCache? preparedChapterCache;
  final NovelReaderPaginationDiagnosticsSink diagnosticsSink;
  final NovelReaderPaginationPerformancePolicy performancePolicy;
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
  NovelReaderComplexHtmlBoundaryCache? _ownedBoundaryCache;
  NovelReaderPreparedChapterCache? _ownedPreparedCache;
  Duration _preparationDuration = Duration.zero;
  int _layoutGeneration = 0;
  String? _lastUnavailableNavigationKey;
  String? _recordedDiagnosticsKey;
  Stopwatch? _layoutStopwatch;
  bool _layoutCacheHit = false;
  Duration? _firstPageDuration;
  String? _performanceFallbackKey;
  Timer? _firstPageBudgetTimer;
  Timer? _fullPlanBudgetTimer;
  bool _planCompleted = false;
  int _cancelledPlanCount = 0;
  int? _appliedChapterEntryRequestId;
  Object? _reportedContentReadyIdentity;
  Object? _reportedContentTerminalIdentity;

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
    _cancelPerformanceTimers();
    _cancelPendingPagination();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final htmlPreferences = widget.preferencesAdapter.map(widget.preferences);
    return DefaultTextStyle.merge(
      style: widget.typography.body,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Knob lives in NovelReaderSpacing.pagedPagePadding (via prefs
          // defaults). Everything below derives the measured page box and the
          // rendered Padding from this one value on purpose — see that doc.
          final pagePadding = widget.preferences.pagePadding
              .clamp(0.0, 96.0)
              .toDouble();
          final topChromeInset = widget.chromeInsets.topInset;
          final bottomChromeInset = widget.chromeInsets.persistentBottomInset;
          final availableWidth = constraints.maxWidth - pagePadding * 2;
          final availableHeight =
              constraints.maxHeight -
              pagePadding * 2 -
              topChromeInset -
              bottomChromeInset;
          final pageIndicatorReservedHeight = math
              .min(
                widget.chromeInsets.pageIndicatorReservedHeight,
                math.max(
                  0,
                  availableHeight -
                      NovelReaderPagedIndicatorLayout.rendererSafetyInset -
                      1,
                ),
              )
              .toDouble();
          final paginationHeight =
              availableHeight -
              pageIndicatorReservedHeight -
              NovelReaderPagedIndicatorLayout.rendererSafetyInset;
          final contentMaxWidth = widget.typography.contentMaxWidth < 160
              ? 160
              : widget.typography.contentMaxWidth;
          final pageWidth = math
              .min(availableWidth, contentMaxWidth)
              .toDouble();
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              pageWidth <= 0 ||
              paginationHeight <= 0) {
            _scheduleContentTerminal('invalid-viewport');
            return _NovelReaderPaginationStateView(
              key: const Key('novel-reader-paged-invalid-viewport'),
              icon: Icons.crop_free,
              message: AppLocalizations.of(context).novelPagedWindowUnavailable,
            );
          }

          return FutureBuilder<NovelReaderPreparedChapter>(
            key: ValueKey<Object?>(_prepareSignature),
            future: _prepareFuture,
            builder: (context, snapshot) {
              final prepared = snapshot.data;
              if (prepared == null) {
                if (snapshot.hasError) {
                  _scheduleContentTerminal((
                    'preparation-error',
                    _prepareSignature,
                  ));
                  return _NovelReaderPaginationFailureView(
                    error: snapshot.error!,
                    onRetry: _retryPreparation,
                    onFallbackToVertical: widget.onFallbackToVertical,
                  );
                }
                return const SizedBox.expand(
                  key: Key('novel-reader-paged-preparing'),
                );
              }

              final key = NovelReaderPaginationKey(
                episodeId: prepared.episodeId,
                contentHash: prepared.contentHash,
                viewportWidthPx: NovelReaderPaginationKey.logicalPixels(
                  pageWidth,
                ),
                viewportHeightPx: NovelReaderPaginationKey.logicalPixels(
                  paginationHeight,
                ),
                typographySignature: _typographySignature(
                  widget.preferences,
                  widget.typography,
                  htmlPreferences,
                  MediaQuery.textScalerOf(context),
                ),
                themeSignature: widget.theme.signature,
                imageDimensionRevision: prepared.imageDimensionRevision,
                rendererRevision: 14,
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
                      _scheduleContentTerminal((
                        'plan-error',
                        key.cacheIdentity,
                      ));
                      return _NovelReaderPaginationFailureView(
                        error: planSnapshot.error!,
                        onRetry: _retryPlan,
                        onFallbackToVertical: widget.onFallbackToVertical,
                      );
                    }
                    return const SizedBox.expand(
                      key: Key('novel-reader-paged-layout-loading'),
                    );
                  }
                  if (plan.pages.isEmpty) {
                    if (progress?.isComplete != true) {
                      return const SizedBox.expand(
                        key: Key('novel-reader-paged-layout-loading'),
                      );
                    }
                    _scheduleContentTerminal(('empty-plan', key.cacheIdentity));
                    return _NovelReaderPaginationStateView(
                      key: const Key('novel-reader-paged-empty'),
                      icon: Icons.article_outlined,
                      message: AppLocalizations.of(context).novelPagedNoContent,
                    );
                  }
                  final isPlanComplete = progress?.isComplete == true;
                  final requestedPage = _requestedPageFor(plan);
                  final navigationIsPending = _hasPendingAnchorNavigation(
                    plan: plan,
                    requestedPage: requestedPage,
                    isPlanComplete: isPlanComplete,
                  );
                  final entryPage = _chapterEntryPageFor(
                    plan: plan,
                    isPlanComplete: isPlanComplete,
                  );
                  final entryIsPending = _hasPendingChapterEntry(
                    plan: plan,
                    entryPage: entryPage,
                    isPlanComplete: isPlanComplete,
                  );
                  if (entryPage != null) {
                    _scheduleChapterEntryApplied(widget.chapterEntryRequest!);
                  }
                  final initialPage =
                      requestedPage ??
                      entryPage ??
                      widget.restorePolicy.resolveAvailablePage(
                        plan: plan,
                        snapshot: widget.progressSnapshot,
                        isPlanComplete: isPlanComplete,
                      );
                  if (navigationIsPending ||
                      entryIsPending ||
                      initialPage == null) {
                    return const SizedBox.expand(
                      key: Key('novel-reader-paged-restoring-position'),
                    );
                  }
                  _scheduleContentReady(key);
                  _firstPageBudgetTimer?.cancel();
                  _firstPageBudgetTimer = null;
                  _firstPageDuration ??= _layoutStopwatch?.elapsed;
                  _ensureFullPlanBudgetTimer(
                    key: key,
                    isComplete: isPlanComplete,
                  );
                  _schedulePerformanceFallbackIfNeeded(
                    plan: plan,
                    key: key,
                    isComplete: isPlanComplete,
                  );
                  if (isPlanComplete) {
                    _planCompleted = true;
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
                          isPageCountFinal: isPlanComplete,
                          initialPage: initialPage,
                          navigationRequest: widget.navigationRequest,
                          pageSeekRequest: widget.pageSeekRequest,
                          targetPage: requestedPage,
                          reverse:
                              widget.preferences.flowMode ==
                              NovelReaderFlowMode.pagedRtl,
                          showProgressIndicator:
                              widget.preferences.showProgressIndicator,
                          previousChapterTitle: widget.previousChapterTitle,
                          nextChapterTitle: widget.nextChapterTitle,
                          chapterTurnPolicy: widget.chapterTurnPolicy,
                          chapterTurnIsInFlight:
                              widget.chapterEntryRequest != null,
                          onTurnToAdjacentChapter:
                              widget.onTurnToAdjacentChapter,
                          contentBottomInset:
                              pageIndicatorReservedHeight +
                              NovelReaderPagedIndicatorLayout
                                  .rendererSafetyInset,
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
      _cancelPendingPagination();
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
      _cancelPendingPagination();
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
    _firstPageDuration = null;
    _performanceFallbackKey = null;
    _cancelPerformanceTimers();
    _recordedDiagnosticsKey = null;
    _planStream = _coordinator!.paginateIncrementally(
      chapter: prepared,
      key: key,
    );
    _planCompleted = false;
    _startFirstPageBudgetTimer(key);
    return _planStream!;
  }

  void _scheduleContentReady(NovelReaderPaginationKey key) {
    final identity = key.cacheIdentity;
    if (_reportedContentReadyIdentity == identity) {
      return;
    }
    _reportedContentReadyIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _planKey == key) {
        widget.onContentReady?.call();
      }
    });
  }

  void _scheduleContentTerminal(Object identity) {
    if (_reportedContentTerminalIdentity == identity) {
      return;
    }
    _reportedContentTerminalIdentity = identity;
    final prepareSignature = _prepareSignature;
    final planKey = _planKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _prepareSignature != prepareSignature ||
          _planKey != planKey) {
        return;
      }
      widget.onContentTerminal?.call();
    });
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
          flowableComplexFragmentCount: plan.flowableComplexFragmentCount,
          complexBoundaryCount: plan.complexBoundaryCount,
          complexBoundaryIndexBuildCount: plan.complexBoundaryIndexBuildCount,
          complexBoundaryIndexCacheHitCount:
              plan.complexBoundaryIndexCacheHitCount,
          complexBoundaryIndexSingleFlightHitCount:
              plan.complexBoundaryIndexSingleFlightHitCount,
          complexSearchProbeCount: plan.complexSearchProbeCount,
          complexSearchCacheHitCount: plan.complexSearchCacheHitCount,
          complexSearchBudgetExceededCount:
              plan.complexSearchBudgetExceededCount,
          minimumComplexFragmentCount: plan.minimumComplexFragmentCount,
          dedicatedImagePageCount: plan.dedicatedImagePageCount,
          dedicatedTablePageCount: plan.dedicatedTablePageCount,
          dedicatedCollapsePageCount: plan.dedicatedCollapsePageCount,
          atomicWidgetPageCount: plan.atomicWidgetPageCount,
          safeTextFallbackCount: plan.safeTextFallbackCount,
          flowableComplexAtomCount: plan.flowableComplexAtomCount,
          atomicWidgetAtomCount: plan.atomicWidgetAtomCount,
          dedicatedContentAtomCount: plan.dedicatedContentAtomCount,
          legacyMarkupNormalizerRevision:
              prepared.legacyMarkupNormalization.revision,
          normalizedLegacyAttributeCount:
              prepared.legacyMarkupNormalization.normalizedAttributeCount,
          legacyMarkupNormalizationReasonCounts:
              prepared.legacyMarkupNormalization.reasonCounts,
          safeTextRunCount: plan.safeTextRunCount,
          firstPageDuration: _firstPageDuration ?? Duration.zero,
          cancelledPlanCount: _cancelledPlanCount,
          availableHeight: key.viewportHeightPx.toDouble(),
          averageTextPageFullness: plan.averageTextPageFullness,
          lowFullnessPageCount: plan.lowFullnessPageCount,
          gapReasonCounts: plan.gapReasonCounts,
          atomKindCounts: plan.atomKindCounts,
          routeCounts: plan.routeCounts,
          routeReasonCounts: plan.routeReasonCounts,
          safeTextFallbackReasonCounts: plan.safeTextFallbackReasonCounts,
          flowabilityFailureReasonCounts: plan.flowabilityFailureReasonCounts,
          measurementSamples: plan.measurementSamples,
        ),
      );
    });
  }

  void _schedulePerformanceFallbackIfNeeded({
    required NovelReaderPaginationPlan plan,
    required NovelReaderPaginationKey key,
    required bool isComplete,
  }) {
    final callback = widget.onFallbackToVertical;
    final firstPageDuration = _firstPageDuration;
    if (callback == null || firstPageDuration == null) {
      return;
    }
    final reason = widget.performancePolicy.evaluate(
      plan: plan,
      firstPageDuration: firstPageDuration,
      fullPlanDuration: isComplete ? _layoutStopwatch?.elapsed : null,
    );
    if (reason == null) {
      return;
    }
    _schedulePerformanceFallback(key: key, reason: reason);
  }

  void _startFirstPageBudgetTimer(NovelReaderPaginationKey key) {
    if (!widget.performancePolicy.enforceBudgets ||
        widget.onFallbackToVertical == null) {
      return;
    }
    _firstPageBudgetTimer = Timer(
      widget.performancePolicy.maximumFirstPageBudget,
      () {
        if (mounted && _planKey == key && _firstPageDuration == null) {
          _schedulePerformanceFallback(
            key: key,
            reason: NovelReaderPaginationPerformanceFallbackReason
                .firstPageBudgetExceeded,
          );
        }
      },
    );
  }

  void _ensureFullPlanBudgetTimer({
    required NovelReaderPaginationKey key,
    required bool isComplete,
  }) {
    if (isComplete) {
      _fullPlanBudgetTimer?.cancel();
      _fullPlanBudgetTimer = null;
      return;
    }
    if (_fullPlanBudgetTimer != null ||
        !widget.performancePolicy.enforceBudgets ||
        widget.onFallbackToVertical == null) {
      return;
    }
    final elapsed = _layoutStopwatch?.elapsed ?? Duration.zero;
    final budget = widget.performancePolicy.maximumFullPlanBudget;
    final remaining = budget - elapsed;
    if (remaining <= Duration.zero) {
      _schedulePerformanceFallback(
        key: key,
        reason: NovelReaderPaginationPerformanceFallbackReason
            .fullPlanBudgetExceeded,
      );
      return;
    }
    _fullPlanBudgetTimer = Timer(remaining, () {
      if (mounted && _planKey == key) {
        _schedulePerformanceFallback(
          key: key,
          reason: NovelReaderPaginationPerformanceFallbackReason
              .fullPlanBudgetExceeded,
        );
      }
    });
  }

  void _schedulePerformanceFallback({
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationPerformanceFallbackReason reason,
  }) {
    final callback = widget.onFallbackToVertical;
    if (callback == null) {
      return;
    }
    final fallbackKey = '${key.cacheIdentity}|${reason.name}';
    if (_performanceFallbackKey == fallbackKey) {
      return;
    }
    _performanceFallbackKey = fallbackKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _planKey == key) {
        callback();
      }
    });
  }

  void _cancelPerformanceTimers() {
    _firstPageBudgetTimer?.cancel();
    _fullPlanBudgetTimer?.cancel();
    _firstPageBudgetTimer = null;
    _fullPlanBudgetTimer = null;
  }

  void _cancelPendingPagination({bool clearCache = false}) {
    if (_planStream != null && !_planCompleted) {
      _cancelledPlanCount += 1;
    }
    _planCompleted = false;
    _planStream = null;
    if (clearCache) {
      _coordinator?.clear();
    } else {
      _coordinator?.cancelPending();
    }
  }

  NovelReaderPaginationCoordinator _defaultCoordinator({
    required BuildContext context,
    required ForumHtmlReaderPreferences htmlPreferences,
  }) {
    final blockSpacingMode = ForumHtmlBlockSpacingMode.discuzLineDivs;
    final rendererBaseStyle = ForumHtmlStylePolicy(
      htmlPreferences,
      theme: widget.theme,
      blockSpacingMode: blockSpacingMode,
    ).baseTextStyle(context);
    final measureAdapter = NovelReaderHtmlPaginationMeasureAdapter(
      hostContext: context,
      theme: widget.theme,
      preferences: htmlPreferences,
      sourceId: widget.episode.episodeId,
      threadId: widget.episode.sourceTid,
      imageCacheOwnerId: widget.episode.sourceTid,
      imageHeaderBuilder: widget.imageHeaderBuilder,
      blockSpacingMode: blockSpacingMode,
    );
    return DefaultNovelReaderPaginationCoordinator(
      pageBreaker: DefaultNovelReaderHybridPaginationPlanner(
        measureAdapter: measureAdapter,
        preferences: htmlPreferences,
        theme: widget.theme,
        baseStyle: rendererBaseStyle,
        textAlign: widget.typography.textAlign,
        textScaler: MediaQuery.textScalerOf(context),
        boundaryCache:
            widget.paginationBoundaryCache ??
            (_ownedBoundaryCache ??= NovelReaderComplexHtmlBoundaryCache()),
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
    _cancelPendingPagination();
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
    _cancelPendingPagination();
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
    _cancelPendingPagination(clearCache: true);
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

  /// Resolves an edge entry into a page index. The `end` edge deliberately
  /// waits for a complete plan: an incremental plan's last page is not yet the
  /// chapter's last page, so landing on it would drop the reader mid-chapter.
  int? _chapterEntryPageFor({
    required NovelReaderPaginationPlan plan,
    required bool isPlanComplete,
  }) {
    final request = widget.chapterEntryRequest;
    if (request == null ||
        request.episodeId != plan.episodeId ||
        plan.pageCount <= 0) {
      return null;
    }
    switch (request.edge) {
      case NovelReaderChapterEdge.start:
        return 0;
      case NovelReaderChapterEdge.end:
        return isPlanComplete ? plan.pageCount - 1 : null;
    }
  }

  /// Retires an entry request that has been resolved into a page, once per
  /// request id. Deferred to the end of the frame because this runs from `build`
  /// and the owner reacts by calling `setState`.
  void _scheduleChapterEntryApplied(NovelReaderChapterEntryRequest request) {
    if (_appliedChapterEntryRequestId == request.requestId) return;
    _appliedChapterEntryRequestId = request.requestId;
    final callback = widget.onChapterEntryApplied;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(request);
    });
  }

  bool _hasPendingChapterEntry({
    required NovelReaderPaginationPlan plan,
    required int? entryPage,
    required bool isPlanComplete,
  }) {
    final request = widget.chapterEntryRequest;
    return !isPlanComplete &&
        entryPage == null &&
        request != null &&
        request.episodeId == plan.episodeId;
  }

  bool _hasPendingAnchorNavigation({
    required NovelReaderPaginationPlan plan,
    required int? requestedPage,
    required bool isPlanComplete,
  }) {
    final request = widget.navigationRequest;
    return !isPlanComplete &&
        requestedPage == null &&
        request != null &&
        request.anchor.episodeId == plan.episodeId;
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
    this.pageSeekRequest,
    this.targetPage,
    required this.reverse,
    required this.showProgressIndicator,
    this.previousChapterTitle,
    this.nextChapterTitle,
    this.chapterTurnPolicy = const NovelReaderChapterTurnPolicy(),
    this.chapterTurnIsInFlight = false,
    this.onTurnToAdjacentChapter,
    required this.contentBottomInset,
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
  final NovelReaderPageSeekRequest? pageSeekRequest;
  final int? targetPage;
  final bool reverse;
  final bool showProgressIndicator;
  final String? previousChapterTitle;
  final String? nextChapterTitle;
  final NovelReaderChapterTurnPolicy chapterTurnPolicy;

  /// True while a chapter switch requested by this gesture is still running.
  final bool chapterTurnIsInFlight;
  final NovelReaderChapterTurnHandler? onTurnToAdjacentChapter;
  final double contentBottomInset;
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
  final ValueNotifier<NovelReaderChapterTurnHint?> _chapterTurnHint =
      ValueNotifier<NovelReaderChapterTurnHint?>(null);
  double _forwardOverscroll = 0;
  double _backwardOverscroll = 0;
  bool _chapterTurnRequested = false;

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
    // A turn that ends without replacing this chapter (it failed, or it landed
    // back here) leaves this state alive, so release the latch on the falling
    // edge instead of keeping the gesture off for good.
    if (_chapterTurnRequested &&
        oldWidget.chapterTurnIsInFlight &&
        !widget.chapterTurnIsInFlight) {
      _chapterTurnRequested = false;
    }
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
    if (oldRequestId != newRequestId && widget.targetPage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.targetPage == null) {
          return;
        }
        _pageController.jumpToPage(widget.targetPage!);
        _emitPosition(widget.targetPage!);
      });
    }
    final oldSeekRequestId = oldWidget.pageSeekRequest?.requestId;
    final seekRequest = widget.pageSeekRequest;
    if (oldSeekRequestId == seekRequest?.requestId || seekRequest == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          seekRequest.episodeId != widget.plan.episodeId ||
          seekRequest.paginationKey != widget.plan.key.layoutFingerprint ||
          seekRequest.pageIndex < 0 ||
          seekRequest.pageIndex >= widget.plan.pageCount) {
        return;
      }
      _jumpToPage(seekRequest.pageIndex);
    });
  }

  @override
  void dispose() {
    _chapterTurnHint.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pageCount = widget.plan.pageCount;
    final totalPageLabel = widget.isPageCountFinal
        ? l10n.novelPages(pageCount)
        : l10n.novelPageCountPending;
    final chapterTitle = NovelTextResolver.chapterTitle(
      l10n,
      widget.episode.episodeTitle,
      widget.episode.sourceTid,
    );
    return Semantics(
      key: const Key('novel-reader-paged-semantics'),
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      label: l10n.novelPageSemantics(
        chapterTitle,
        _currentPage + 1,
        totalPageLabel,
      ),
      value: l10n.novelPageValue(_currentPage + 1, totalPageLabel),
      increasedValue: _currentPage + 1 < pageCount
          ? l10n.novelNextPageSemantics(_currentPage + 2)
          : null,
      decreasedValue: _currentPage > 0
          ? l10n.novelPreviousPageSemantics(_currentPage)
          : null,
      onIncrease: _currentPage + 1 < pageCount
          ? () => _jumpToPage(_currentPage + 1)
          : null,
      onDecrease: _currentPage > 0 ? () => _jumpToPage(_currentPage - 1) : null,
      child: Stack(
        key: const Key('novel-reader-paged-page-session'),
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: PageView.builder(
              key: const Key('novel-reader-paged-page-view'),
              controller: _pageController,
              reverse: widget.reverse,
              allowImplicitScrolling: false,
              // A chapter that fits on a single page has no scrollable extent, so
              // the default physics would refuse the drag outright and the
              // turn-past-the-edge gesture would be dead there. This only
              // overrides `shouldAcceptUserOffset`; `Scrollable` still appends the
              // platform physics underneath, so clamping/bouncing behaviour and
              // page snapping are untouched.
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: pageCount,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final page = widget.plan.pages[index];
                return Padding(
                  key: ValueKey<String>(
                    'novel-reader-paged-content-inset-${page.index}',
                  ),
                  padding: EdgeInsets.only(bottom: widget.contentBottomInset),
                  child: _NovelReaderPagedPage(
                    key: ValueKey<String>(
                      'novel-reader-paged-page-${page.index}',
                    ),
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
                  ),
                );
              },
            ),
          ),
          _NovelReaderChapterTurnHintOverlay(
            hint: _chapterTurnHint,
            bottomInset: widget.contentBottomInset,
          ),
          if (widget.showProgressIndicator)
            Positioned(
              key: const Key('novel-reader-page-indicator'),
              right: NovelReaderPagedIndicatorLayout.rightInset,
              bottom: NovelReaderPagedIndicatorLayout.bottomInset,
              child: Text(
                l10n.novelPageIndicator(
                  _currentPage + 1,
                  widget.isPageCountFinal
                      ? '$pageCount'
                      : l10n.novelPageCountPending,
                ),
                key: const Key('novel-reader-page-indicator-text'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: NovelReaderPagedIndicatorLayout.fontSize,
                  height: NovelReaderPagedIndicatorLayout.lineHeight,
                  letterSpacing: 0,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  /// Turns a drag past either edge of the chapter into a chapter switch.
  ///
  /// Sign convention: `PageView` maps the *last* page to `maxScrollExtent`
  /// regardless of [reverse] (reverse only flips the viewport axis direction,
  /// not the child order), so positive overscroll always means "past the last
  /// page" for both pagedLtr and pagedRtl.
  ///
  /// Only drag-driven overscroll counts. A ballistic settle after a fling also
  /// reports overscroll on bouncing physics, and letting that commit would turn
  /// a flick at the edge into an accidental chapter switch.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _resetChapterTurnTracking();
      return false;
    }
    if (notification is OverscrollNotification) {
      if (notification.dragDetails == null) {
        return false;
      }
      _accumulateOverscroll(notification.overscroll, notification.metrics);
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) {
        return false;
      }
      // Bouncing physics move the position past the boundary instead of
      // reporting an overscroll delta, so read the overshoot off the metrics.
      final metrics = notification.metrics;
      final beyondEnd = metrics.pixels - metrics.maxScrollExtent;
      final beforeStart = metrics.minScrollExtent - metrics.pixels;
      if (beyondEnd > 0) {
        _observeOverscroll(forward: beyondEnd, metrics: metrics);
      } else if (beforeStart > 0) {
        _observeOverscroll(backward: beforeStart, metrics: metrics);
      }
      return false;
    }
    if (notification is ScrollEndNotification) {
      _commitChapterTurnIfRequested(notification.metrics);
      return false;
    }
    return false;
  }

  void _accumulateOverscroll(double overscroll, ScrollMetrics metrics) {
    if (overscroll > 0) {
      _observeOverscroll(
        forward: _forwardOverscroll + overscroll,
        metrics: metrics,
      );
    } else if (overscroll < 0) {
      _observeOverscroll(
        backward: _backwardOverscroll - overscroll,
        metrics: metrics,
      );
    }
  }

  /// Keeps the peak pull in each direction. Clamping physics report deltas while
  /// bouncing physics report absolute overshoot; taking the max makes both
  /// sources agree on "how far did the reader actually pull".
  void _observeOverscroll({
    double? forward,
    double? backward,
    required ScrollMetrics metrics,
  }) {
    if (forward != null) {
      _forwardOverscroll = math.max(_forwardOverscroll, forward);
    }
    if (backward != null) {
      _backwardOverscroll = math.max(_backwardOverscroll, backward);
    }
    _updateChapterTurnHint(metrics);
  }

  void _resetChapterTurnTracking() {
    _forwardOverscroll = 0;
    _backwardOverscroll = 0;
    _chapterTurnHint.value = null;
  }

  NovelReaderChapterEdge? _pendingChapterTurnEdge() {
    if (_forwardOverscroll <= 0 && _backwardOverscroll <= 0) {
      return null;
    }
    final edge = _forwardOverscroll >= _backwardOverscroll
        ? NovelReaderChapterEdge.end
        : NovelReaderChapterEdge.start;
    return _chapterTitleFor(edge) == null ? null : edge;
  }

  String? _chapterTitleFor(NovelReaderChapterEdge edge) {
    final title = switch (edge) {
      NovelReaderChapterEdge.start => widget.previousChapterTitle,
      NovelReaderChapterEdge.end => widget.nextChapterTitle,
    };
    final trimmed = title?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  double _overscrollFor(NovelReaderChapterEdge edge) {
    return switch (edge) {
      NovelReaderChapterEdge.start => _backwardOverscroll,
      NovelReaderChapterEdge.end => _forwardOverscroll,
    };
  }

  void _updateChapterTurnHint(ScrollMetrics metrics) {
    if (!_canTurnChapter()) {
      _chapterTurnHint.value = null;
      return;
    }
    final edge = _pendingChapterTurnEdge();
    if (edge == null) {
      _chapterTurnHint.value = null;
      return;
    }
    final distance = _overscrollFor(edge);
    final viewportDimension = metrics.viewportDimension;
    if (!widget.chapterTurnPolicy.shouldRevealHint(
      overscrollDistance: distance,
      viewportDimension: viewportDimension,
    )) {
      _chapterTurnHint.value = null;
      return;
    }
    _chapterTurnHint.value = NovelReaderChapterTurnHint(
      edge: edge,
      chapterTitle: _chapterTitleFor(edge)!,
      isReadyToCommit: widget.chapterTurnPolicy.shouldCommit(
        overscrollDistance: distance,
        viewportDimension: viewportDimension,
      ),
    );
  }

  bool _canTurnChapter() {
    return widget.onTurnToAdjacentChapter != null &&
        !widget.chapterTurnIsInFlight &&
        !_chapterTurnRequested;
  }

  /// Latches only on an *accepted* turn. A declined turn must leave the gesture
  /// armed: nothing is in flight, so no falling edge is coming to release it.
  void _commitChapterTurnIfRequested(ScrollMetrics metrics) {
    final edge = _pendingChapterTurnEdge();
    final shouldTurn =
        edge != null &&
        _canTurnChapter() &&
        widget.chapterTurnPolicy.shouldCommit(
          overscrollDistance: _overscrollFor(edge),
          viewportDimension: metrics.viewportDimension,
        );
    _resetChapterTurnTracking();
    if (!shouldTurn) {
      return;
    }
    _chapterTurnRequested = widget.onTurnToAdjacentChapter!(edge);
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

class _NovelReaderChapterTurnHintOverlay extends StatelessWidget {
  const _NovelReaderChapterTurnHintOverlay({
    required this.hint,
    required this.bottomInset,
  });

  final ValueListenable<NovelReaderChapterTurnHint?> hint;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset + NovelReaderChapterTurnHintLayout.bottomInset,
      child: ValueListenableBuilder<NovelReaderChapterTurnHint?>(
        valueListenable: hint,
        builder: (context, value, _) {
          if (value == null) {
            return const SizedBox.shrink();
          }
          return Center(
            child: DecoratedBox(
              key: const Key('novel-reader-chapter-turn-hint'),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: NovelReaderChapterTurnHintLayout.backgroundOpacity,
                ),
                borderRadius: const BorderRadius.all(
                  Radius.circular(
                    NovelReaderChapterTurnHintLayout.cornerRadius,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal:
                      NovelReaderChapterTurnHintLayout.horizontalPadding,
                  vertical: NovelReaderChapterTurnHintLayout.verticalPadding,
                ),
                child: Text(
                  NovelTextResolver.chapterTurnHint(
                    AppLocalizations.of(context),
                    value,
                  ),
                  key: const Key('novel-reader-chapter-turn-hint-text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
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
      blockSpacingMode: ForumHtmlBlockSpacingMode.discuzLineDivs,
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
      label: AppLocalizations.of(
        context,
      ).novelPageOfTotalSemantics(page.index + 1, plan.pageCount),
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
  });

  final IconData icon;
  final String message;

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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        key: const Key('novel-reader-pagination-failure'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_outlined, size: 34),
          const SizedBox(height: 12),
          Text(l10n.novelPagedLayoutFailed),
          const SizedBox(height: 6),
          Text(
            LibraryErrorSummary.resolve(l10n, error),
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
                label: Text(l10n.commonRetry),
              ),
              if (onFallbackToVertical != null)
                FilledButton.icon(
                  key: const Key('novel-reader-pagination-fallback'),
                  onPressed: onFallbackToVertical,
                  icon: const Icon(Icons.view_agenda_outlined),
                  label: Text(l10n.novelReturnToScroll),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
