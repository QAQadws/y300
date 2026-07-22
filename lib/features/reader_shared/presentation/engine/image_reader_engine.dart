import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/data/export/reader_image_export_providers.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';
import 'package:y300/features/reader_shared/domain/metrics/reader_performance_metrics.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_display_settings_sheet.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_page_indicator_overlay.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_paged_image_fit_surface.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_position_state.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_vertical_position_driver.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_preload_coordinator.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';

/// 通用图片阅读壳：垂直/横向模式、缩放、overlay 工具栏、进度滑块、页码浮层、
/// 显示设置、滚动锚定补偿、解码预热。
///
/// 引擎零业务知识，一切业务差异（标题、章节、书签、缓存、过场卡、图片内容本体、
/// 阅读进度落地）通过 [ReaderCapability] 注入。漫画与帖子图片阅读器共用本引擎。
///
/// 行为对齐自原 `ComicReaderPage`：滚动锚定/补偿、滑块 commit 状态机、PageController
/// 同步等时序敏感逻辑均按原实现迁移，仅把业务部分替换为能力回调。
class ImageReaderEngine extends ConsumerStatefulWidget {
  const ImageReaderEngine({
    super.key,
    required this.capability,
    this.flowPolicy = ContinuousImageFlowPolicy.comicVerticalReading,
    this.listKey = const Key('image-reader-engine-image-list'),
    this.pageKey = const Key('image-reader-engine-page-view'),
    this.slotKeyPrefix = 'image-reader-engine-image-slot',
  });

  final ReaderCapability capability;
  final ContinuousImageFlowPolicy flowPolicy;
  final Key listKey;
  final Key pageKey;
  final String slotKeyPrefix;

  @override
  ConsumerState<ImageReaderEngine> createState() => _ImageReaderEngineState();
}

class _ImageReaderEngineState extends ConsumerState<ImageReaderEngine>
    implements ReaderEngineActions {
  late final ScrollController _scrollController;
  PageController? _pageController;
  String? _pageControllerOwnerId;
  late final ReaderOverlayController _overlayController;
  late final ReaderGestureCoordinator _gestureCoordinator;
  late final ValueNotifier<bool> _zoomGate;
  late final ValueNotifier<int> _activePagedIndex;
  ScrollHoldController? _pagedZoomScrollHold;
  final Map<int, bool> _pagedHorizontalOverflowByIndex = <int, bool>{};
  final Map<String, double> _resolvedPagedAspectRatioByItemId =
      <String, double>{};

  int _lastKnownIndex = 0;
  ReaderSequencePosition _pagedPosition = const ReaderSequencePosition.image(0);
  final Set<String> _reportedTailSurfaceKeys = <String>{};
  final Set<String> _reportedAdvanceSurfaceKeys = <String>{};
  final Set<String> _reportedAdjacentPreloadKeys = <String>{};

  // 滑块拖动会话 + commit 锁状态机（迁移自 ComicReaderPage）。
  int? _sliderPreviewIndex;
  DateTime? _lastSliderCommitAt;
  bool _isSliderCommitInFlight = false;
  int? _pendingCommittedIndex;
  int? _activeSeekGeneration;

  bool _isPageIndicatorHighlighted = false;
  Timer? _pageIndicatorDimTimer;

  final Set<int> _reportedVisibleImageIndexes = <int>{};

  String? _lastOwnerId;
  ReaderPositionState? _positionState;
  bool _exitFlushed = false;

  // These counters are diagnostic-only. Position and preload behavior must
  // remain independent from observability state.
  int _readerSessionGeneration = 0;
  int _verticalViewportPrimedGeneration = -1;
  int _restoreGeneration = 0;
  int _seekGeneration = 0;
  ReaderModePreference _diagnosticMode = ReaderModePreference.vertical;
  bool _positionRetryScheduled = false;
  String? _exportingIdentity;

  // 连续图片高度/锚定基础设施（迁移自 ComicReaderPage）。
  static const ContinuousImageLayoutResolver _layoutResolver =
      ContinuousImageLayoutResolver();
  static const ContinuousImageViewportTracker _viewportTracker =
      ContinuousImageViewportTracker(layoutResolver: _layoutResolver);
  static const ContinuousImageScrollAnchorCoordinator _anchorCoordinator =
      ContinuousImageScrollAnchorCoordinator(layoutResolver: _layoutResolver);
  final InMemoryContinuousImageExtentRegistry _extentRegistry =
      InMemoryContinuousImageExtentRegistry();
  late final ReaderImageSessionStore _imageSessionStore;
  late final ReaderImageSessionPreloadCoordinator _sessionPreloadCoordinator;
  late final ReaderVerticalPositionDriver _verticalPositionDriver;
  final ReaderPerformanceMetricsCollector _performanceMetrics =
      ReaderPerformanceMetricsCollector();
  final Map<String, GlobalKey> _verticalItemAnchors = <String, GlobalKey>{};

  List<ContinuousImageItem> _latestItems = const <ContinuousImageItem>[];
  double _pendingScrollCompensationDelta = 0;
  ScrollPosition? _observedScrollPosition;

  ReaderCapability get _capability => widget.capability;

  ReaderTailSurface? get _tailSurface => _capability.tailSurface;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onVerticalScroll);
    _overlayController = ReaderOverlayController()
      ..addListener(_onOverlayVisibilityChanged);
    _gestureCoordinator = ReaderGestureCoordinator();
    _zoomGate = ValueNotifier<bool>(false);
    _activePagedIndex = ValueNotifier<int>(0);
    _imageSessionStore = ReaderImageSessionStore();
    _sessionPreloadCoordinator = ReaderImageSessionPreloadCoordinator(
      sessionStore: _imageSessionStore,
      onScheduled: _recordSessionPreloadScheduled,
      onResult: _recordSessionPreload,
      performanceMetrics: _performanceMetrics,
    );
    _verticalPositionDriver = ReaderVerticalPositionDriver(
      isReady: () => mounted && _scrollController.hasClients,
      currentOffset: () => _scrollController.offset,
      clampOffset: _clampVerticalOffset,
      jumpTo: _scrollController.jumpTo,
      estimateOffset: _estimateVerticalOffset,
      exactOffset: _resolveExactVerticalOffset,
      waitForLayout: _waitForVerticalLayout,
    );
  }

  @override
  void dispose() {
    if (!_exitFlushed) {
      unawaited(_capability.onExit());
    }
    _observedScrollPosition?.isScrollingNotifier.removeListener(
      _onScrollActivityChanged,
    );
    _scrollController
      ..removeListener(_onVerticalScroll)
      ..dispose();
    _releasePagedZoomScrollHold();
    _pageController?.dispose();
    _overlayController
      ..removeListener(_onOverlayVisibilityChanged)
      ..dispose();
    _gestureCoordinator.dispose();
    _zoomGate.dispose();
    _activePagedIndex.dispose();
    _pageIndicatorDimTimer?.cancel();
    _verticalPositionDriver.dispose();
    _sessionPreloadCoordinator.dispose();
    _imageSessionStore.dispose();
    _disposeTailSurface();
    super.dispose();
  }
  // ENGINE_BODY_PLACEHOLDER

  @override
  Widget build(BuildContext context) {
    final preferencesState = ref.watch(readerPreferencesControllerProvider);
    final preferences = preferencesState.value ?? ReaderPreferences.defaults();
    final mode = _readerMode(preferences);
    final content = _capability.content;
    _diagnosticMode = preferences.readerMode;

    if (content.isEmpty) {
      return const Scaffold(body: Center(child: Text('没有可阅读图片')));
    }

    final positionState = _resetIfOwnerChanged(content, preferences.readerMode);
    _syncPageControllerIfNeeded(
      mode,
      positionState.committedLogicalIndex,
      content.ownerId,
    );
    _restorePositionIfNeeded(mode, preferences.readerMode, content);

    final total = content.length;
    final engineContext = _engineContext(preferences, total);

    return Scaffold(
      body: Stack(
        children: [
          ReaderOverlayScaffold(
            controller: _overlayController,
            gestureCoordinator: _gestureCoordinator,
            topBar: _buildTopBar(engineContext),
            bottomBar: _buildBottomBar(engineContext, preferences),
            onLeftTap: mode == ContinuousImageReaderMode.vertical
                ? null
                : () => _turnPageByTap(
                    mode: preferences.readerMode,
                    total: total,
                    isLeftTap: true,
                  ),
            onRightTap: mode == ContinuousImageReaderMode.vertical
                ? null
                : () => _turnPageByTap(
                    mode: preferences.readerMode,
                    total: total,
                    isLeftTap: false,
                  ),
            bottomSafeFraction: mode == ContinuousImageReaderMode.vertical
                ? 0.2
                : 0,
            tapZonesBlockedListenable: _zoomGate,
            child: _buildContentLayer(
              context: context,
              content: content,
              mode: mode,
              preferences: preferences,
              engineContext: engineContext,
            ),
          ),
          ReaderPageIndicatorOverlay(
            visible:
                !_overlayController.isMenuVisible &&
                preferences.showPageIndicator,
            highlighted: _isPageIndicatorHighlighted,
            currentPage: (_sliderPreviewIndex ?? _lastKnownIndex) + 1,
            totalPages: total,
            positionLabel: _sequencePositionLabel(),
          ),
        ],
      ),
    );
  }

  Widget _buildVertical(
    ReaderContent content,
    ReaderPreferences preferences,
    ReaderEngineContext engineContext,
  ) {
    final items = content.items;
    _latestItems = items;
    _syncVerticalItemAnchors(items);
    final verticalTrailing = _buildVerticalTrailingSpec(engineContext);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncScrollPositionActivityListener();
        if (_verticalViewportPrimedGeneration != _readerSessionGeneration) {
          // A ListView may build cached rows without scrolling. Resolve the
          // initial viewport here so only the actual reading position is
          // reported to the business capability. This is once per owner;
          // running it on every rebuild can create a persistent UI loop while
          // image extents are settling.
          _verticalViewportPrimedGeneration = _readerSessionGeneration;
          _onVerticalScroll();
        }
        _submitSessionPreloadWindow(
          focusIndex: _lastKnownIndex,
          scrollDirection: ContinuousImageScrollDirection.idle,
        );
      }
    });
    final reader = NotificationListener<ScrollNotification>(
      onNotification: _onVerticalScrollNotification,
      child: ContinuousImageReaderView(
        items: items,
        mode: ContinuousImageReaderMode.vertical,
        scrollController: _scrollController,
        scrollCacheExtent: ScrollCacheExtent.pixels(
          MediaQuery.sizeOf(context).height *
              widget.flowPolicy.viewportCacheExtentFactor,
        ),
        layoutResolver: _layoutResolver,
        onExtentResolved: _recordExtent,
        verticalListKey: widget.listKey,
        slotKeyPrefix: widget.slotKeyPrefix,
        verticalItemAnchorKeyBuilder: (item, _) =>
            _verticalItemAnchors[item.id]!,
        verticalTrailingBuilder: verticalTrailing.builder,
        verticalTrailingItemCount: verticalTrailing.itemCount,
        verticalTrailingItemBuilder: verticalTrailing.indexedBuilder,
        itemBuilder: (context, item, index, {required paged}) {
          return _buildImage(item, index, preferences, paged: false);
        },
      ),
    );
    return ReaderZoomableImage(
      key: const Key('image-reader-engine-vertical-zoom-surface'),
      gestureCoordinator: _gestureCoordinator,
      behavior: ReaderZoomBehavior.continuousVertical,
      onZoomStateChanged: _onVerticalReaderZoomStateChanged,
      child: reader,
    );
  }

  Widget _buildPaged(ReaderContent content, ReaderPreferences preferences) {
    final items = content.items;
    final tail = _tailSurface;
    final pageController = _pageController;
    _latestItems = items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precachePagedWindow(_lastKnownIndex);
      }
    });
    return ReaderPagedSwipeGate(
      blockedListenable: _zoomGate,
      child: ContinuousImageReaderView(
        key: ValueKey<String>('reader-paged-owner-${content.ownerId}'),
        items: items,
        mode: ContinuousImageReaderMode.horizontal,
        pageController: pageController,
        horizontalPhysics: _pagedHorizontalOverflowActive(preferences)
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        reverse: preferences.readerMode == ReaderModePreference.rtl,
        onPageChanged: pageController == null
            ? null
            : (pageIndex) => _onPageChanged(
                pageIndex,
                ownerId: content.ownerId,
                pageController: pageController,
              ),
        horizontalPageKey: widget.pageKey,
        horizontalPagePadding: EdgeInsets.all(
          preferences.pageSpacing.clamp(0.0, 48.0).toDouble(),
        ),
        horizontalTrailingBuilder: tail == null
            ? null
            : (context) => _buildPagedTail(context, tail),
        horizontalAdvanceBuilder: tail == null || !tail.hasAdvance
            ? null
            : (context) => _buildPagedAdvance(context, tail),
        layoutResolver: _layoutResolver,
        onExtentResolved: _recordExtent,
        itemBuilder: (context, item, index, {required paged}) {
          return _buildImage(item, index, preferences, paged: true);
        },
      ),
    );
  }

  Widget _buildImage(
    ContinuousImageItem item,
    int index,
    ReaderPreferences preferences, {
    required bool paged,
  }) {
    final ownerId = item.ownerId;
    final sessionGeneration = _readerSessionGeneration;
    final pageController = _pageController;
    final aspectRatio = paged
        ? _resolvedPagedAspectRatioByItemId[item.id] ??
              _layoutResolver.resolveInitialHint(item: item).aspectRatio
        : null;
    final sessionBinding = _imageSessionStore.bindingFor(
      item,
      initialLocalPath: _capability.initialLocalPathFor(item),
    );
    final image = _capability.buildImageContent(
      context,
      ReaderImageBuildSpec(
        item: item,
        index: index,
        paged: paged,
        fit: _imageFitFor(preferences.pageFit),
        sessionBinding: sessionBinding,
        expectedDisplaySize: _expectedImageDisplaySize(
          preferences,
          paged: paged,
          aspectRatio: aspectRatio,
        ),
        onDimensionsResolved: (size) => _onImageDimensionsResolved(
          ownerId: ownerId,
          sessionGeneration: sessionGeneration,
          itemId: item.id,
          paged: paged,
          size: size,
        ),
        onRetry: () => unawaited(_retrySessionImage(index)),
      ),
    );
    if (!paged) {
      return image;
    }
    final fittedImage = ReaderPagedImageFitSurface(
      key: ValueKey<String>(
        'reader-paged-fit-$ownerId-${item.id}-'
        '${preferences.pageFit.name}-${preferences.readerMode.name}',
      ),
      ownerId: ownerId,
      itemId: item.id,
      pageIndex: index,
      pageFit: preferences.pageFit,
      readerMode: preferences.readerMode,
      aspectRatio: aspectRatio!,
      onHorizontalOverflowChanged: (hasOverflow) {
        _onPagedHorizontalOverflowChanged(
          ownerId: ownerId,
          sessionGeneration: sessionGeneration,
          pageIndex: index,
          hasOverflow: hasOverflow,
        );
      },
      onEdgeTurnRequested: (intent) {
        _onPagedEdgeTurnRequested(
          ownerId: ownerId,
          sessionGeneration: sessionGeneration,
          sourcePageIndex: index,
          expectedPageController: pageController,
          intent: intent,
        );
      },
      child: image,
    );
    return ReaderZoomableImage(
      key: ValueKey<String>('reader-zoom-surface-${item.id}'),
      gestureCoordinator: _gestureCoordinator,
      activePageIndexListenable: _activePagedIndex,
      pageIndex: index,
      resetToken: '${preferences.pageFit.name}:${preferences.readerMode.name}',
      onZoomStateChanged: (isZoomed) =>
          _onPagedImageZoomStateChanged(index, isZoomed),
      child: fittedImage,
    );
  }

  bool _pagedHorizontalOverflowActive(ReaderPreferences preferences) {
    if (preferences.pageFit != ReaderPageFitPreference.fitHeight ||
        !_pagedPosition.isImage) {
      return false;
    }
    final activeIndex = _pagedPosition.index;
    return activeIndex != null &&
        _pagedHorizontalOverflowByIndex[activeIndex] == true;
  }

  void _onImageDimensionsResolved({
    required String ownerId,
    required int sessionGeneration,
    required String itemId,
    required bool paged,
    required Size size,
  }) {
    if (!paged ||
        !mounted ||
        _lastOwnerId != ownerId ||
        _capability.content.ownerId != ownerId ||
        _readerSessionGeneration != sessionGeneration ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    final aspectRatio = size.width / size.height;
    final previous = _resolvedPagedAspectRatioByItemId[itemId];
    if (previous != null && (previous - aspectRatio).abs() < 0.0001) {
      return;
    }
    _resolvedPagedAspectRatioByItemId[itemId] = aspectRatio;
    setState(() {});
  }

  void _onPagedHorizontalOverflowChanged({
    required String ownerId,
    required int sessionGeneration,
    required int pageIndex,
    required bool hasOverflow,
  }) {
    if (!mounted ||
        _lastOwnerId != ownerId ||
        _capability.content.ownerId != ownerId ||
        _readerSessionGeneration != sessionGeneration) {
      return;
    }
    final previous = _pagedHorizontalOverflowByIndex[pageIndex] == true;
    if (hasOverflow) {
      _pagedHorizontalOverflowByIndex[pageIndex] = true;
    } else {
      _pagedHorizontalOverflowByIndex.remove(pageIndex);
    }
    if (previous == hasOverflow ||
        !_pagedPosition.isImage ||
        _pagedPosition.index != pageIndex) {
      return;
    }
    setState(() {});
  }

  void _onPagedEdgeTurnRequested({
    required String ownerId,
    required int sessionGeneration,
    required int sourcePageIndex,
    required PageController? expectedPageController,
    required ReaderPageTurnIntent intent,
  }) {
    final pageController = _pageController;
    final content = _capability.content;
    if (!mounted ||
        _zoomGate.value ||
        expectedPageController == null ||
        !identical(pageController, expectedPageController) ||
        !expectedPageController.hasClients ||
        _lastOwnerId != ownerId ||
        content.ownerId != ownerId ||
        _readerSessionGeneration != sessionGeneration ||
        !_pagedPosition.isImage ||
        _pagedPosition.index != sourcePageIndex ||
        _activePagedIndex.value != sourcePageIndex) {
      return;
    }
    final currentPage = expectedPageController.page;
    if (currentPage == null || (currentPage - sourcePageIndex).abs() > 0.5) {
      return;
    }
    final delta = intent == ReaderPageTurnIntent.next ? 1 : -1;
    final target = sourcePageIndex + delta;
    if (target < 0 || target >= _pagedPageCount(content.length)) {
      return;
    }
    if (target < content.length) {
      _promoteSessionSeekTarget(target);
    }
    expectedPageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _syncVerticalItemAnchors(List<ContinuousImageItem> items) {
    final activeIds = items.map((item) => item.id).toSet();
    _verticalItemAnchors.removeWhere(
      (itemId, _) => !activeIds.contains(itemId),
    );
    for (final item in items) {
      _verticalItemAnchors.putIfAbsent(
        item.id,
        () => GlobalKey(debugLabel: 'reader-vertical-anchor-${item.id}'),
      );
    }
  }

  _ReaderVerticalTrailingSpec _buildVerticalTrailingSpec(
    ReaderEngineContext engineContext,
  ) {
    final tail = _tailSurface;
    final legacyTrailing = _capability.verticalTrailingBuilder(engineContext);
    final tailCount = tail?.verticalItemCount ?? 0;
    if (tailCount <= 0) {
      return _ReaderVerticalTrailingSpec.single(legacyTrailing);
    }
    return _ReaderVerticalTrailingSpec(
      itemCount: tailCount + (legacyTrailing == null ? 0 : 1),
      indexedBuilder: (context, index) {
        if (index < tailCount) {
          return _buildVerticalTailItem(context, tail!, index);
        }
        return legacyTrailing!(context);
      },
    );
  }

  Widget _buildPagedTail(BuildContext context, ReaderTailSurface tail) {
    _scheduleAdjacentPreloadIfReady(tail);
    return KeyedSubtree(
      key: Key('reader-tail-${tail.id}'),
      child: tail.buildPaged(context, _tailActions(tail)),
    );
  }

  Widget _buildPagedAdvance(BuildContext context, ReaderTailSurface tail) {
    return KeyedSubtree(
      key: Key('reader-tail-advance-${tail.id}'),
      child: tail.buildAdvance(context, _tailActions(tail)),
    );
  }

  Widget _buildVerticalTailItem(
    BuildContext context,
    ReaderTailSurface tail,
    int index,
  ) {
    if (index == 0) {
      _scheduleTailVisible(tail);
    }
    _scheduleAdjacentPreloadIfReady(tail);
    return KeyedSubtree(
      key: Key('reader-tail-vertical-${tail.id}-$index'),
      child: tail.buildVerticalItem(context, _tailActions(tail), index),
    );
  }

  ReaderTailActions _tailActions(ReaderTailSurface tail) {
    return ReaderTailActions(
      onRetry: () => _invokeTailCallback(tail, tail.onRetry),
      onAdvance: () => _invokeTailCallback(tail, tail.onAdvance),
    );
  }

  void _scheduleTailVisible(ReaderTailSurface tail) {
    final key = '${_lastOwnerId ?? '-'}:${tail.id}';
    if (!_reportedTailSurfaceKeys.add(key)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isCurrentTail(tail)) {
        return;
      }
      _invokeTailCallback(tail, tail.onVerticalVisible);
    });
  }

  void _scheduleAdjacentPreloadIfReady(ReaderTailSurface tail) {
    if (!tail.isAdjacentPreloadReady) {
      return;
    }
    final ownerId = _lastOwnerId;
    if (ownerId == null) {
      return;
    }
    final key = '$ownerId:${tail.id}';
    if (!_reportedAdjacentPreloadKeys.add(key)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isCurrentTail(tail)) {
        return;
      }
      unawaited(_prepareAdjacentPreload(tail, key));
    });
  }

  Future<void> _prepareAdjacentPreload(
    ReaderTailSurface tail,
    String key,
  ) async {
    final plan = await _capability.buildAdjacentPreloadPlan();
    if (!mounted || !_isCurrentTail(tail)) {
      return;
    }
    final ownerId = _lastOwnerId;
    if (ownerId == null || !_reportedAdjacentPreloadKeys.contains(key)) {
      return;
    }
    if (plan == null || plan.images.isEmpty) {
      return;
    }
    _sessionPreloadCoordinator.submitAdjacentWindow(
      context: context,
      plan: plan,
      precacheService: ref.read(forumImagePrecacheServiceProvider),
      expectedDisplaySize: _expectedPreloadDisplaySize(),
    );
  }

  void _invokeTailCallback(
    ReaderTailSurface tail,
    FutureOr<void> Function() callback,
  ) {
    unawaited(_invokeTailCallbackAndWait(tail, callback));
  }

  Future<void> _invokeTailCallbackAndWait(
    ReaderTailSurface tail,
    FutureOr<void> Function() callback,
  ) async {
    if (!_isCurrentTail(tail)) {
      return;
    }
    try {
      await callback();
    } catch (error, stack) {
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekFailed,
        status: 'tailCallbackFailed',
        result: error.runtimeType.toString(),
        message: stack.toString().split('\n').first,
      );
    }
  }

  bool _isCurrentTail(ReaderTailSurface tail) {
    return mounted && identical(_tailSurface, tail);
  }

  void _disposeTailSurface() {
    final tail = _tailSurface;
    if (tail == null) {
      return;
    }
    try {
      tail.dispose();
    } catch (_) {
      // A tail is optional chrome; disposal must never block reader teardown.
    }
  }

  String? _sequencePositionLabel() {
    final tail = _tailSurface;
    final position = _pagedPosition;
    if (tail == null || position.isImage) {
      return null;
    }
    if (position.isAdvance) return null;
    return tail.indicatorLabel;
  }

  double? _estimateVerticalOffset(int targetIndex) {
    if (!_scrollController.hasClients || _latestItems.isEmpty) {
      return null;
    }
    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    if (!position.hasContentDimensions || maxScroll <= 0) {
      return null;
    }
    final clampedIndex = targetIndex.clamp(0, _latestItems.length - 1).toInt();
    final estimated = _extentRegistry.estimateOffsetForIndex(
      clampedIndex,
      _latestItems,
      crossAxisExtent: MediaQuery.sizeOf(context).width,
      resolver: _layoutResolver,
    );
    if (estimated.isFinite && (estimated > 0 || clampedIndex == 0)) {
      return estimated;
    }
    if (_latestItems.length <= 1) {
      return 0;
    }
    return maxScroll * (clampedIndex / (_latestItems.length - 1));
  }

  double? _resolveExactVerticalOffset(int targetIndex) {
    if (!_scrollController.hasClients ||
        targetIndex < 0 ||
        targetIndex >= _latestItems.length) {
      return null;
    }
    final item = _latestItems[targetIndex];
    final itemContext = _verticalItemAnchors[item.id]?.currentContext;
    final renderObject = itemContext?.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) {
      return null;
    }
    return viewport.getOffsetToReveal(renderObject, 0).offset;
  }

  double _clampVerticalOffset(double offset) {
    if (!_scrollController.hasClients || !offset.isFinite) {
      return 0;
    }
    final position = _scrollController.position;
    return offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  Future<void> _waitForVerticalLayout() async {
    await WidgetsBinding.instance.endOfFrame;
  }

  bool _onVerticalScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _verticalPositionDriver.cancelActive(
        ReaderVerticalSeekCancelReason.userScroll,
      );
    }
    return false;
  }

  BoxFit _imageFitFor(ReaderPageFitPreference fit) {
    switch (fit) {
      case ReaderPageFitPreference.fitWidth:
        return BoxFit.fitWidth;
      case ReaderPageFitPreference.fitHeight:
        return BoxFit.fitHeight;
      case ReaderPageFitPreference.contain:
        return BoxFit.contain;
    }
  }

  Color _backgroundColor(ReaderPreferences preferences) {
    final scheme = Theme.of(context).colorScheme;
    switch (preferences.background) {
      case ReaderBackgroundPreference.followTheme:
        return scheme.surface;
      case ReaderBackgroundPreference.black:
        return Colors.black;
      case ReaderBackgroundPreference.white:
        return Colors.white;
      case ReaderBackgroundPreference.gray:
        return const Color(0xFF202124);
    }
  }

  ReaderEngineContext _engineContext(ReaderPreferences preferences, int total) {
    return ReaderEngineContext(
      currentIndex: _lastKnownIndex,
      totalCount: total,
      mode: _readerMode(preferences),
      actions: this,
    );
  }

  // --- owner reset / page controller sync / restore ---

  ReaderPositionState _resetIfOwnerChanged(
    ReaderContent content,
    ReaderModePreference readerMode,
  ) {
    final current = _positionState;
    if (current != null && current.ownerId == content.ownerId) {
      return current;
    }
    final previous = _lastOwnerId;
    _verticalPositionDriver.cancelActive(
      ReaderVerticalSeekCancelReason.ownerChanged,
    );
    if (previous != null) {
      _extentRegistry.clearForOwner(previous);
    }
    _verticalItemAnchors.clear();
    _performanceMetrics.reset();
    final initialIndex = content.initialIndex
        .clamp(0, content.length - 1)
        .toInt();
    final next = ReaderPositionState(
      ownerId: content.ownerId,
      initialLogicalIndex: initialIndex,
    );
    _positionState = next;
    _lastOwnerId = content.ownerId;
    _latestItems = const <ContinuousImageItem>[];
    _pendingScrollCompensationDelta = 0;
    _reportedVisibleImageIndexes.clear();
    _reportedTailSurfaceKeys.clear();
    _reportedAdvanceSurfaceKeys.clear();
    _reportedAdjacentPreloadKeys.clear();
    _pagedHorizontalOverflowByIndex.clear();
    _resolvedPagedAspectRatioByItemId.clear();
    _pagedPosition = ReaderSequencePosition.image(initialIndex);
    _setZoomGate(false, paged: false);
    _activePagedIndex.value = initialIndex;
    _lastKnownIndex = initialIndex;
    _isSliderCommitInFlight = false;
    _pendingCommittedIndex = null;
    _activeSeekGeneration = null;
    _sliderPreviewIndex = null;
    _lastSliderCommitAt = null;
    _positionRetryScheduled = false;
    _sessionPreloadCoordinator.resetSession(
      readerOwnerId: content.ownerId,
      items: content.items,
    );
    _readerSessionGeneration += 1;
    _verticalViewportPrimedGeneration = -1;
    _restoreGeneration = 0;
    _seekGeneration = 0;
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.readerSessionCreated,
      index: _lastKnownIndex,
      mode: readerMode,
      generation: _readerSessionGeneration,
      status: 'created',
      result: 'ready',
      message: _readerMemoryBudgetLogFields(),
    );
    return next;
  }

  String _readerMemoryBudgetLogFields() {
    final imageCache = PaintingBinding.instance.imageCache;
    const policy = ReaderImageSessionPreloadPolicy.aggressiveReaderSession;
    return 'decodedRadius=${policy.decodedRadius} '
        'diskRadius=${policy.diskRadius} '
        'maxConcurrent=${policy.maxConcurrentTasks} '
        'imageCacheMaxEntries=${imageCache.maximumSize} '
        'imageCacheMaxBytes=${imageCache.maximumSizeBytes}';
  }

  void _syncPageControllerIfNeeded(
    ContinuousImageReaderMode mode,
    int initialIndex,
    String ownerId,
  ) {
    if (mode == ContinuousImageReaderMode.vertical) {
      return;
    }
    final expectedInitialPage = initialIndex.clamp(0, 1 << 20).toInt();
    final controller = _pageController;
    if (controller == null || _pageControllerOwnerId != ownerId) {
      // The page controller belongs to one reader owner. Persisting its
      // scroll offset would restore a previous chapter's tail/sentinel page
      // and clamp it to the new chapter's last image.
      _pageController = PageController(
        initialPage: expectedInitialPage,
        keepPage: false,
      );
      _pageControllerOwnerId = ownerId;
      if (controller != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.dispose();
        });
      }
      return;
    }
  }

  void _restorePositionIfNeeded(
    ContinuousImageReaderMode mode,
    ReaderModePreference readerMode,
    ReaderContent content,
  ) {
    final positionState = _positionState;
    if (positionState == null ||
        positionState.ownerId != content.ownerId ||
        _isSliderCommitInFlight ||
        (!positionState.needsInitialRestore &&
            (mode == ContinuousImageReaderMode.vertical ||
                positionState.pendingPagedSeek == null))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _isSliderCommitInFlight ||
          !_isCurrentPositionState(positionState, content.length) ||
          _diagnosticMode != readerMode) {
        return;
      }
      if (positionState.needsInitialRestore) {
        if (mode == ContinuousImageReaderMode.vertical) {
          await _restoreVertical(content, positionState);
        } else {
          _restorePaged(content, readerMode, positionState);
        }
      }
      if (mode == ContinuousImageReaderMode.horizontal) {
        _applyPendingPagedSeekIfPossible(content, positionState);
      }
    });
  }

  Future<void> _restoreVertical(
    ReaderContent content,
    ReaderPositionState positionState,
  ) async {
    if (!positionState.needsInitialRestore ||
        !_isCurrentPositionState(positionState, content.length)) {
      return;
    }
    final generation = ++_restoreGeneration;
    final targetIndex = positionState.initialLogicalIndex;
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.initialRestoreStarted,
      index: targetIndex,
      mode: ReaderModePreference.vertical,
      generation: generation,
      targetIndex: targetIndex,
      status: 'started',
      result: 'pending',
    );
    if (!_scrollController.hasClients) {
      _recordInitialRestoreCompleted(
        index: targetIndex,
        mode: ReaderModePreference.vertical,
        generation: generation,
        status: 'pending',
        result: 'controllerNotAttached',
      );
      _schedulePositionRetry();
      return;
    }

    final targetOffset = _capability.initialVerticalScrollOffset;
    var result = 'noStoredOffset';
    ReaderVerticalSeekResult? verticalSeek;
    if (_scrollController.offset == 0 &&
        targetOffset != null &&
        targetOffset > 0) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        final offset = targetOffset.clamp(0.0, maxScroll).toDouble();
        if (offset > 0) {
          _scrollController.jumpTo(offset);
          result = 'jumped';
        }
      } else {
        result = 'noScrollableExtent';
      }
    } else if (_scrollController.offset == 0 && targetIndex > 0) {
      verticalSeek = await _verticalPositionDriver.seekToIndex(targetIndex);
      _performanceMetrics.recordSeek(
        elapsed: verticalSeek.elapsed,
        correctionDelta: verticalSeek.correctionDelta,
      );
      if (verticalSeek.status == ReaderVerticalSeekStatus.cancelled) {
        positionState.consumeInitialRestore();
        _recordInitialRestoreCompleted(
          index: _lastKnownIndex,
          mode: ReaderModePreference.vertical,
          generation: generation,
          status: 'cancelled',
          result: verticalSeek.cancelReason?.name ?? 'cancelled',
          elapsedMs: verticalSeek.elapsed.inMilliseconds,
          correctionDelta: verticalSeek.correctionDelta,
        );
        _scheduleVerticalProgressSync();
        return;
      }
      result = verticalSeek.exact ? 'indexExact' : 'indexEstimated';
    } else if (_scrollController.offset != 0) {
      result = 'alreadyMoved';
    }

    if (!_isCurrentPositionState(positionState, content.length)) {
      return;
    }
    positionState.consumeInitialRestore();
    _commitLogicalIndex(targetIndex);
    _recordInitialRestoreCompleted(
      index: targetIndex,
      mode: ReaderModePreference.vertical,
      generation: generation,
      status: 'consumed',
      result: result,
      elapsedMs: verticalSeek?.elapsed.inMilliseconds,
      correctionDelta: verticalSeek?.correctionDelta,
    );
  }

  void _restorePaged(
    ReaderContent content,
    ReaderModePreference readerMode,
    ReaderPositionState positionState,
  ) {
    if (!positionState.needsInitialRestore ||
        !_isCurrentPositionState(positionState, content.length)) {
      return;
    }
    final generation = ++_restoreGeneration;
    final targetPage = positionState.initialLogicalIndex;
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.initialRestoreStarted,
      index: targetPage,
      mode: readerMode,
      generation: generation,
      targetIndex: targetPage,
      status: 'started',
      result: 'pending',
    );
    final pageController = _pageController;
    if (pageController == null || !pageController.hasClients) {
      _recordInitialRestoreCompleted(
        index: targetPage,
        mode: readerMode,
        generation: generation,
        status: 'pending',
        result: 'controllerNotAttached',
      );
      _schedulePositionRetry();
      return;
    }
    if (pageController.position.isScrollingNotifier.value) {
      _recordInitialRestoreCompleted(
        index: targetPage,
        mode: readerMode,
        generation: generation,
        status: 'pending',
        result: 'controllerStillScrolling',
      );
      _schedulePositionRetry();
      return;
    }
    final page = pageController.page;
    var result = 'alreadyAtTarget';
    if (page == null || (page - targetPage).abs() >= 0.01) {
      pageController.jumpToPage(targetPage);
      result = 'jumped';
    }
    positionState.consumeInitialRestore();
    _commitLogicalIndex(targetPage);
    _reportActualImageVisible(
      index: targetPage,
      ownerId: content.ownerId,
      sessionGeneration: _readerSessionGeneration,
    );
    _recordInitialRestoreCompleted(
      index: targetPage,
      mode: readerMode,
      generation: generation,
      status: 'consumed',
      result: result,
    );
  }

  void _recordInitialRestoreCompleted({
    required int index,
    required ReaderModePreference mode,
    required int generation,
    required String status,
    required String result,
    int? elapsedMs,
    double? correctionDelta,
  }) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.initialRestoreCompleted,
      index: index,
      mode: mode,
      generation: generation,
      targetIndex: index,
      status: status,
      result: result,
      elapsedMs: elapsedMs,
      correctionDelta: correctionDelta,
    );
  }

  bool _isCurrentPositionState(
    ReaderPositionState positionState,
    int expectedItemCount,
  ) {
    final content = _capability.content;
    return identical(_positionState, positionState) &&
        content.ownerId == positionState.ownerId &&
        content.length == expectedItemCount;
  }

  void _commitLogicalIndex(int index) {
    final positionState = _positionState;
    if (positionState != null) {
      positionState.commitLogicalIndex(index);
    }
    _lastKnownIndex = index;
    if (_diagnosticMode != ReaderModePreference.vertical &&
        _activePagedIndex.value != index) {
      _setZoomGate(false, paged: true);
      _activePagedIndex.value = index;
    }
  }

  void _schedulePositionRetry() {
    if (_positionRetryScheduled) {
      return;
    }
    _positionRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionRetryScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  bool _queueOrApplyPagedSeek({
    required ReaderContent content,
    required ReaderPositionState positionState,
    required int targetIndex,
    required int generation,
    bool recordReached = false,
  }) {
    positionState.queuePagedSeek(index: targetIndex, generation: generation);
    return _applyPendingPagedSeekIfPossible(
      content,
      positionState,
      recordReached: recordReached,
    );
  }

  bool _applyPendingPagedSeekIfPossible(
    ReaderContent content,
    ReaderPositionState positionState, {
    bool recordReached = true,
  }) {
    final pending = positionState.pendingPagedSeek;
    if (pending == null ||
        !_isCurrentPositionState(positionState, content.length)) {
      return false;
    }
    if (pending.logicalIndex < 0 || pending.logicalIndex >= content.length) {
      positionState.clearPendingPagedSeek(pending);
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekFailed,
        index: positionState.committedLogicalIndex,
        generation: pending.generation,
        targetIndex: pending.logicalIndex,
        status: 'rejected',
        result: 'targetOutOfRange',
      );
      return false;
    }
    final pageController = _pageController;
    if (pageController == null || !pageController.hasClients) {
      _schedulePositionRetry();
      return false;
    }
    final page = pageController.page;
    if (page == null || (page - pending.logicalIndex).abs() >= 0.01) {
      pageController.jumpToPage(pending.logicalIndex);
    }
    positionState.clearPendingPagedSeek(pending);
    _commitLogicalIndex(pending.logicalIndex);
    if (recordReached) {
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekReached,
        index: pending.logicalIndex,
        generation: pending.generation,
        targetIndex: pending.logicalIndex,
        status: 'completed',
        result: 'pendingApplied',
      );
    }
    return true;
  }

  // --- vertical scroll progress + active index ---

  void _onVerticalScroll() {
    if (!_scrollController.hasClients || _isSliderCommitInFlight) {
      return;
    }
    _syncScrollPositionActivityListener();
    _applyPendingScrollCompensationIfIdle();
    _hideReaderMenuForContentMotion();
    _pulsePageIndicator();
    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }
    final items = _latestItems;
    final total = items.length;
    if (total == 0) {
      return;
    }
    final ratio = position.maxScrollExtent <= 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent)
              .clamp(0.0, 1.0)
              .toDouble();
    final viewport = _viewportTracker.resolve(
      items: items,
      extentRegistry: _extentRegistry,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      crossAxisExtent: MediaQuery.sizeOf(context).width,
      userScrollDirection: _viewportTracker.directionFromPosition(position),
    );
    final index =
        viewport.lastEndVisibleIndex ??
        viewport.lastVisibleIndex ??
        viewport.firstVisibleIndex ??
        ((total - 1) * ratio).round();
    _reportActualImageVisible(
      index: index,
      ownerId: _lastOwnerId ?? _capability.content.ownerId,
      sessionGeneration: _readerSessionGeneration,
    );
    if (index != _lastKnownIndex) {
      _commitLogicalIndex(index);
      _capability.onScrollProgress(index: index, offset: position.pixels);
      _submitSessionPreloadWindow(
        focusIndex: index,
        scrollDirection: viewport.userScrollDirection,
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _recordExtent(ContinuousImageExtent extent) {
    final previous = _extentRegistry.extentOf(extent.itemId);
    final plan = _planScrollCompensation(previous, extent);
    _extentRegistry.record(extent);
    _applyScrollCompensationPlan(plan);
  }

  ContinuousImageScrollCompensationPlan _planScrollCompensation(
    ContinuousImageExtent? previous,
    ContinuousImageExtent next,
  ) {
    if (!_scrollController.hasClients || _latestItems.isEmpty) {
      return ContinuousImageScrollCompensationPlan.none('noScrollContext');
    }
    _syncScrollPositionActivityListener();
    final position = _scrollController.position;
    return _anchorCoordinator.planForExtentChange(
      previousExtent: previous,
      nextExtent: next,
      items: _latestItems,
      extentRegistry: _extentRegistry,
      policy: widget.flowPolicy,
      metrics: ContinuousImageScrollAnchorMetrics(
        scrollOffset: position.pixels,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
        viewportExtent: position.viewportDimension,
        userScrollDirection: _viewportTracker.directionFromPosition(position),
        isScrollActivityInProgress: position.isScrollingNotifier.value,
      ),
    );
  }

  void _applyScrollCompensationPlan(
    ContinuousImageScrollCompensationPlan plan,
  ) {
    if (!plan.shouldCompensate || !_scrollController.hasClients) {
      return;
    }
    if (plan.shouldApplyImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        final position = _scrollController.position;
        if (position.isScrollingNotifier.value ||
            _viewportTracker.directionFromPosition(position) !=
                ContinuousImageScrollDirection.idle) {
          _pendingScrollCompensationDelta += plan.delta;
          _syncScrollPositionActivityListener();
          return;
        }
        final targetOffset = plan.targetOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        _scrollController.jumpTo(targetOffset);
      });
      return;
    }
    _pendingScrollCompensationDelta += plan.delta;
    _syncScrollPositionActivityListener();
  }

  void _syncScrollPositionActivityListener() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (identical(_observedScrollPosition, position)) {
      return;
    }
    _observedScrollPosition?.isScrollingNotifier.removeListener(
      _onScrollActivityChanged,
    );
    _observedScrollPosition = position
      ..isScrollingNotifier.addListener(_onScrollActivityChanged);
  }

  void _onScrollActivityChanged() {
    _applyPendingScrollCompensationIfIdle();
  }

  void _applyPendingScrollCompensationIfIdle() {
    if (_pendingScrollCompensationDelta == 0 || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.isScrollingNotifier.value ||
        _viewportTracker.directionFromPosition(position) !=
            ContinuousImageScrollDirection.idle) {
      return;
    }
    final delta = _pendingScrollCompensationDelta;
    _pendingScrollCompensationDelta = 0;
    final targetOffset = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((targetOffset - position.pixels).abs() > 0.5) {
      _scrollController.jumpTo(targetOffset);
    }
  }

  void _reportActualImageVisible({
    required int index,
    required String ownerId,
    required int sessionGeneration,
  }) {
    final content = _capability.content;
    if (index < 0 ||
        index >= content.length ||
        _lastOwnerId != ownerId ||
        _readerSessionGeneration != sessionGeneration ||
        content.ownerId != ownerId ||
        !_reportedVisibleImageIndexes.add(index)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _lastOwnerId != ownerId ||
          _readerSessionGeneration != sessionGeneration ||
          _capability.content.ownerId != ownerId ||
          index < 0 ||
          index >= _capability.content.length) {
        return;
      }
      _capability.onImageVisible(index);
    });
  }

  // --- paged turning + page change ---

  Future<void> _onPageChanged(
    int pageIndex, {
    required String ownerId,
    required PageController pageController,
  }) async {
    if (!mounted ||
        _lastOwnerId != ownerId ||
        _capability.content.ownerId != ownerId ||
        !identical(_pageController, pageController)) {
      return;
    }
    final content = _capability.content;
    final page = pageController.page;
    if (page != null && (page - pageIndex).abs() > 0.5) {
      return;
    }
    final positionState = _positionState;
    if (positionState != null &&
        positionState.needsInitialRestore &&
        positionState.ownerId == content.ownerId &&
        pageIndex != content.initialIndex) {
      return;
    }
    final wasOnImage = _pagedPosition.isImage;
    final position = _pagedPositionForPage(pageIndex, content.length);
    if (!position.isImage) {
      _hideReaderMenuForContentMotion();
      _pagedPosition = position;
      if (position.isTail) {
        final tail = _tailSurface;
        if (tail != null) {
          final key = '${_lastOwnerId ?? '-'}:${tail.id}';
          if (_reportedTailSurfaceKeys.add(key)) {
            _invokeTailCallback(tail, tail.onVisible);
          }
        }
      } else if (position.isAdvance) {
        final tail = _tailSurface;
        if (tail != null) {
          final key = '${_lastOwnerId ?? '-'}:${tail.id}';
          if (_reportedAdvanceSurfaceKeys.add(key)) {
            unawaited(_invokeAdvanceCallbackAndAllowRetry(tail, key));
          }
        }
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _pagedPosition = position;
    _reportActualImageVisible(
      index: pageIndex,
      ownerId: ownerId,
      sessionGeneration: _readerSessionGeneration,
    );
    if (pageIndex == _lastKnownIndex) {
      if (!wasOnImage && mounted) {
        setState(() {});
      }
      return;
    }
    final previousIndex = _lastKnownIndex;
    _hideReaderMenuForContentMotion();
    _pulsePageIndicator();
    _commitLogicalIndex(pageIndex);
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.pageChanged,
      index: pageIndex,
      generation: _isSliderCommitInFlight ? _seekGeneration : null,
      targetIndex: _pendingCommittedIndex,
      status: 'arrived',
      result: 'pageChanged',
    );
    _capability.onScrollProgress(index: pageIndex, offset: 0);
    _submitSessionPreloadWindow(
      focusIndex: pageIndex,
      scrollDirection: pageIndex < previousIndex
          ? ContinuousImageScrollDirection.reverse
          : ContinuousImageScrollDirection.forward,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _invokeAdvanceCallbackAndAllowRetry(
    ReaderTailSurface tail,
    String key,
  ) async {
    await _invokeTailCallbackAndWait(tail, tail.onAdvance);
    if (mounted) {
      // A successful owner change clears this set during the next session
      // reset. On failure, removing the key lets the user retry after
      // returning to the comment tail; never animate the old PageView back.
      _reportedAdvanceSurfaceKeys.remove(key);
    }
  }

  void _turnPageByTap({
    required ReaderModePreference mode,
    required int total,
    required bool isLeftTap,
  }) {
    if (_zoomGate.value) {
      return;
    }
    final pageController = _pageController;
    if (pageController == null || !pageController.hasClients) {
      return;
    }
    final current =
        pageController.page?.round() ??
        _pagedPageForPosition(_pagedPosition, total);
    final isRtl = mode == ReaderModePreference.rtl;
    final isPreviousAction = isRtl ? !isLeftTap : isLeftTap;
    final delta = isPreviousAction ? -1 : 1;
    final target = (current + delta)
        .clamp(0, _pagedPageCount(total) - 1)
        .toInt();
    if (target == current) {
      return;
    }
    if (target < total) {
      _promoteSessionSeekTarget(target);
    }
    pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  int _pagedPageCount(int imageCount) {
    final tail = _tailSurface;
    if (tail == null) {
      return imageCount;
    }
    return imageCount + 1 + (tail.hasAdvance ? 1 : 0);
  }

  int _pagedPageForPosition(ReaderSequencePosition position, int imageCount) {
    if (position.isImage) {
      return (position.index ?? 0).clamp(0, imageCount - 1).toInt();
    }
    if (position.isTail) {
      return imageCount;
    }
    return imageCount + 1;
  }

  ReaderSequencePosition _pagedPositionForPage(int pageIndex, int imageCount) {
    if (pageIndex < imageCount) {
      return ReaderSequencePosition.image(pageIndex);
    }
    final tail = _tailSurface;
    if (tail == null) {
      return ReaderSequencePosition.image(
        pageIndex.clamp(0, imageCount - 1).toInt(),
      );
    }
    if (pageIndex == imageCount) {
      return ReaderSequencePosition.tail(tail.id);
    }
    if (tail.hasAdvance && pageIndex == imageCount + 1) {
      return ReaderSequencePosition.advance('${tail.id}:advance');
    }
    return ReaderSequencePosition.tail(tail.id);
  }

  // --- slider commit state machine ---

  void _onProgressChangeStart(double sliderValue, int total) {
    final index = sliderValue.round().clamp(0, total - 1).toInt();
    setState(() => _sliderPreviewIndex = index);
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.seekPreviewChanged,
      index: index,
      generation: _seekGeneration,
      targetIndex: index,
      status: 'started',
      result: 'preview',
    );
  }

  void _onProgressChanged(double sliderValue, int total) {
    final index = sliderValue.round().clamp(0, total - 1).toInt();
    final didChange = _sliderPreviewIndex != index;
    setState(() => _sliderPreviewIndex = index);
    if (didChange) {
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekPreviewChanged,
        index: index,
        generation: _seekGeneration,
        targetIndex: index,
        status: 'changed',
        result: 'preview',
      );
    }
  }

  Future<void> _onProgressChangeEnd({
    required double sliderValue,
    required ReaderPreferences preferences,
    required int total,
  }) async {
    final content = _capability.content;
    final positionState = _positionState;
    final targetIndex = sliderValue.round().clamp(0, total - 1).toInt();
    if (!mounted ||
        positionState == null ||
        positionState.ownerId != content.ownerId ||
        total != content.length ||
        targetIndex < 0 ||
        targetIndex >= content.length) {
      if (mounted) {
        setState(() => _sliderPreviewIndex = null);
      }
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekFailed,
        index: _lastKnownIndex,
        mode: preferences.readerMode,
        generation: _seekGeneration,
        targetIndex: targetIndex,
        status: 'rejected',
        result: 'staleOwnerOrItemCount',
      );
      return;
    }
    final now = DateTime.now();
    if (_lastSliderCommitAt != null &&
        now.difference(_lastSliderCommitAt!) <
            const Duration(milliseconds: 120)) {
      return;
    }
    _lastSliderCommitAt = now;
    final previousIndex = _lastKnownIndex;
    final seekGeneration = ++_seekGeneration;
    final seekStopwatch = Stopwatch()..start();
    var seekCorrectionDelta = 0.0;
    var performanceRecorded = false;
    _activeSeekGeneration = seekGeneration;
    if (positionState.needsInitialRestore) {
      positionState.consumeInitialRestore();
    }
    _pulsePageIndicator();

    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.seekStarted,
      index: previousIndex,
      mode: preferences.readerMode,
      generation: seekGeneration,
      targetIndex: targetIndex,
      status: 'inFlight',
      result: 'pending',
    );

    setState(() {
      _isSliderCommitInFlight = true;
      _pendingCommittedIndex = targetIndex;
      _sliderPreviewIndex = targetIndex;
    });
    _promoteSessionSeekTarget(targetIndex);

    try {
      var reached = false;
      if (preferences.readerMode == ReaderModePreference.vertical) {
        final verticalResult = await _jumpVerticalToIndex(targetIndex);
        seekCorrectionDelta = verticalResult.correctionDelta;
        _performanceMetrics.recordSeek(
          elapsed: verticalResult.elapsed,
          correctionDelta: seekCorrectionDelta,
        );
        performanceRecorded = true;
        if (verticalResult.status == ReaderVerticalSeekStatus.cancelled) {
          _recordSeekSuperseded(
            seekGeneration: seekGeneration,
            targetIndex: targetIndex,
            mode: preferences.readerMode,
            reason: verticalResult.cancelReason?.name ?? 'cancelled',
            elapsedMs: verticalResult.elapsed.inMilliseconds,
            correctionDelta: seekCorrectionDelta,
          );
          _scheduleVerticalProgressSync();
          return;
        }
        if (!verticalResult.reached) {
          throw StateError('verticalSeekUnavailable');
        }
        if (!_isCurrentPositionState(positionState, total)) {
          _recordSeekSuperseded(
            seekGeneration: seekGeneration,
            targetIndex: targetIndex,
            mode: preferences.readerMode,
            elapsedMs: verticalResult.elapsed.inMilliseconds,
            correctionDelta: seekCorrectionDelta,
          );
          return;
        }
        _commitLogicalIndex(targetIndex);
        reached = true;
      } else {
        reached = _queueOrApplyPagedSeek(
          content: content,
          positionState: positionState,
          targetIndex: targetIndex,
          generation: seekGeneration,
        );
        if (reached) {
          _performanceMetrics.recordSeek(
            elapsed: seekStopwatch.elapsed,
            correctionDelta: 0,
          );
          performanceRecorded = true;
        }
      }

      if (!_isCurrentPositionState(positionState, total)) {
        _recordSeekSuperseded(
          seekGeneration: seekGeneration,
          targetIndex: targetIndex,
          mode: preferences.readerMode,
          elapsedMs: seekStopwatch.elapsed.inMilliseconds,
          correctionDelta: seekCorrectionDelta,
        );
        return;
      }
      await _capability.onSeek(
        index: targetIndex,
        offset:
            preferences.readerMode == ReaderModePreference.vertical &&
                _scrollController.hasClients
            ? _scrollController.offset
            : 0,
      );
      if (!_isCurrentPositionState(positionState, total)) {
        _recordSeekSuperseded(
          seekGeneration: seekGeneration,
          targetIndex: targetIndex,
          mode: preferences.readerMode,
        );
        return;
      }
      if (reached) {
        _recordReaderDiagnostic(
          type: ContinuousImageDiagnosticEventType.seekReached,
          index: targetIndex,
          mode: preferences.readerMode,
          generation: seekGeneration,
          targetIndex: targetIndex,
          status: 'completed',
          result: 'reached',
          elapsedMs: seekStopwatch.elapsed.inMilliseconds,
          correctionDelta: seekCorrectionDelta,
        );
      } else {
        _recordReaderDiagnostic(
          type: ContinuousImageDiagnosticEventType.seekStarted,
          index: positionState.committedLogicalIndex,
          mode: preferences.readerMode,
          generation: seekGeneration,
          targetIndex: targetIndex,
          status: 'pendingAttach',
          result: 'queued',
        );
      }
    } catch (error) {
      if (!performanceRecorded) {
        _performanceMetrics.recordSeek(
          elapsed: seekStopwatch.elapsed,
          correctionDelta: seekCorrectionDelta,
        );
      }
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekFailed,
        index: _lastKnownIndex,
        mode: preferences.readerMode,
        generation: seekGeneration,
        targetIndex: targetIndex,
        status: 'failed',
        result: error.runtimeType.toString(),
        elapsedMs: seekStopwatch.elapsed.inMilliseconds,
        correctionDelta: seekCorrectionDelta,
      );
    } finally {
      _releaseSliderCommitLock(seekGeneration);
    }
  }

  void _recordSeekSuperseded({
    required int seekGeneration,
    required int targetIndex,
    required ReaderModePreference mode,
    String reason = 'ownerOrItemCountChanged',
    int? elapsedMs,
    double? correctionDelta,
  }) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.seekSuperseded,
      index: _lastKnownIndex,
      mode: mode,
      generation: seekGeneration,
      targetIndex: targetIndex,
      status: 'superseded',
      result: reason,
      elapsedMs: elapsedMs,
      correctionDelta: correctionDelta,
    );
  }

  void _releaseSliderCommitLock(int seekGeneration) {
    if (_activeSeekGeneration != seekGeneration) {
      return;
    }
    void release() {
      _isSliderCommitInFlight = false;
      _pendingCommittedIndex = null;
      _sliderPreviewIndex = null;
      _activeSeekGeneration = null;
    }

    if (mounted) {
      setState(release);
      if (_diagnosticMode == ReaderModePreference.vertical) {
        _scheduleVerticalProgressSync();
      }
    } else {
      release();
    }
  }

  Future<ReaderVerticalSeekResult> _jumpVerticalToIndex(int targetIndex) {
    return _verticalPositionDriver.seekToIndex(targetIndex);
  }

  void _scheduleVerticalProgressSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isSliderCommitInFlight) {
        _onVerticalScroll();
      }
    });
  }

  void _precachePagedWindow(int centerIndex) {
    _submitSessionPreloadWindow(
      focusIndex: centerIndex,
      scrollDirection: ContinuousImageScrollDirection.idle,
    );
  }

  void _submitSessionPreloadWindow({
    required int focusIndex,
    required ContinuousImageScrollDirection scrollDirection,
  }) {
    final items = _latestItems;
    if (!mounted || items.isEmpty) {
      return;
    }
    _sessionPreloadCoordinator.submitWindow(
      context: context,
      content: ReaderContent(
        ownerId: _lastOwnerId ?? _capability.content.ownerId,
        items: items,
        initialIndex: _capability.content.initialIndex,
      ),
      focusIndex: focusIndex,
      scrollDirection: scrollDirection,
      capability: _capability,
      precacheService: ref.read(forumImagePrecacheServiceProvider),
      expectedDisplaySize: _expectedPreloadDisplaySize(),
    );
  }

  void _promoteSessionSeekTarget(int index) {
    final items = _latestItems;
    if (!mounted || items.isEmpty) {
      return;
    }
    _sessionPreloadCoordinator.promoteSeekTarget(
      context: context,
      content: ReaderContent(
        ownerId: _lastOwnerId ?? _capability.content.ownerId,
        items: items,
        initialIndex: _capability.content.initialIndex,
      ),
      index: index,
      capability: _capability,
      precacheService: ref.read(forumImagePrecacheServiceProvider),
      expectedDisplaySize: _expectedPreloadDisplaySize(),
    );
  }

  Future<void> _retrySessionImage(int index) async {
    final items = _latestItems;
    if (!mounted || items.isEmpty) {
      return;
    }
    await _sessionPreloadCoordinator.prepareOne(
      context: context,
      content: ReaderContent(
        ownerId: _lastOwnerId ?? _capability.content.ownerId,
        items: items,
        initialIndex: _capability.content.initialIndex,
      ),
      index: index,
      capability: _capability,
      precacheService: ref.read(forumImagePrecacheServiceProvider),
      expectedDisplaySize: _expectedPreloadDisplaySize(),
      force: true,
    );
  }

  Size? _expectedPreloadDisplaySize() {
    if (!mounted) {
      return null;
    }
    final preferences =
        ref.read(readerPreferencesControllerProvider).value ??
        ReaderPreferences.defaults();
    return _expectedImageDisplaySize(
      preferences,
      paged: _diagnosticMode != ReaderModePreference.vertical,
    );
  }

  Size _expectedImageDisplaySize(
    ReaderPreferences preferences, {
    required bool paged,
    double? aspectRatio,
  }) {
    final mediaSize = MediaQuery.sizeOf(context);
    if (!paged) {
      return mediaSize;
    }
    final inset = preferences.pageSpacing.clamp(0.0, 48.0).toDouble() * 2;
    final viewport = Size(
      (mediaSize.width - inset).clamp(1.0, double.infinity).toDouble(),
      (mediaSize.height - inset).clamp(1.0, double.infinity).toDouble(),
    );
    final ratio = aspectRatio;
    if (ratio == null || !ratio.isFinite || ratio <= 0) {
      return viewport;
    }
    switch (preferences.pageFit) {
      case ReaderPageFitPreference.fitWidth:
        return Size(viewport.width, viewport.width / ratio);
      case ReaderPageFitPreference.fitHeight:
        return Size(viewport.height * ratio, viewport.height);
      case ReaderPageFitPreference.contain:
        return applyBoxFit(
          BoxFit.contain,
          Size(ratio, 1),
          viewport,
        ).destination;
    }
  }

  void _recordSessionPreloadScheduled(
    ReaderImageSessionPreloadScheduled scheduled,
  ) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.prefetchScheduled,
      ownerId: scheduled.readerOwnerId,
      itemId: scheduled.itemId,
      index: scheduled.imageIndex,
      source: scheduled.spec.sourceUrl,
      generation: scheduled.generation,
      status: 'scheduled',
      result: 'pending',
      preloadKind: scheduled.kind.name,
      applied: true,
    );
  }

  void _recordSessionPreload(ReaderImageSessionPreloadResult result) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.prefetchCompleted,
      ownerId: result.readerOwnerId,
      itemId: result.itemId,
      index: result.imageIndex,
      source: result.spec.sourceUrl,
      generation: result.generation,
      status: 'completed',
      result: result.result.success ? 'success' : 'failure',
      preloadKind: result.kind.name,
      applied: result.applied,
      elapsedMs: result.elapsed.inMilliseconds,
      message:
          'diskAttempted=${result.result.diskCacheAttempted} '
          'diskHit=${result.result.fromDiskCache} '
          'decodeAttempted=${result.result.decodePrecacheAttempted} '
          'decoded=${result.result.decoded} '
          'stale=${result.stale} '
          'providerMatched=${result.providerMatched} '
          'reason=${result.result.failureReason ?? '-'} '
          '${_performanceMetrics.snapshot.toLogFields()}',
    );
  }

  // --- mode + display settings sheets ---

  @override
  void openDisplaySettings() {
    unawaited(_showDisplaySettingsSheet());
  }

  @override
  void openModeSheet() {
    unawaited(_showModeSheet());
  }

  @override
  void cycleReaderMode() {
    final currentMode =
        ref.read(readerPreferencesControllerProvider).value?.readerMode ??
        ReaderPreferences.defaults().readerMode;
    final modes = ReaderModePreference.values;
    final nextMode = modes[(currentMode.index + 1) % modes.length];
    unawaited(_onReaderModeChanged(nextMode));
  }

  @override
  void exportCurrentImage() {
    unawaited(_exportCurrentImage());
  }

  Future<void> _exportCurrentImage() async {
    final content = _capability.content;
    if (content.isEmpty) {
      return;
    }
    final index = _lastKnownIndex.clamp(0, content.length - 1).toInt();
    final item = content.items[index];
    final metadata = _capability.exportMetadataFor(item);
    if (metadata == null) {
      _showExportMessage('当前图片不支持下载');
      return;
    }
    final identity = '${content.ownerId}:${item.id}';
    if (_exportingIdentity == identity) {
      return;
    }
    _exportingIdentity = identity;
    _overlayController.hideMenu();
    _showExportMessage('正在保存当前图片');
    try {
      final result = await ref
          .read(readerImageExportServiceProvider)
          .export(
            ReaderImageExportRequest(
              cacheRequest: _capability.cacheRequestFor(item),
              metadata: metadata,
            ),
          );
      if (!mounted || _exportingIdentity != identity) {
        return;
      }
      _showExportMessage(
        result.success
            ? '已保存到${result.destination?.displayLocation ?? '系统照片'}'
            : _exportFailureMessage(result.failureReason),
      );
    } finally {
      if (_exportingIdentity == identity) {
        _exportingIdentity = null;
      }
    }
  }

  void _showExportMessage(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _exportFailureMessage(ReaderImageExportFailureReason? reason) {
    return switch (reason) {
      ReaderImageExportFailureReason.cacheUnavailable => '图片暂不可用，请重试',
      ReaderImageExportFailureReason.permissionDenied => '没有照片库写入权限，请在系统设置中允许',
      ReaderImageExportFailureReason.permissionRestricted => '照片库权限受系统限制',
      ReaderImageExportFailureReason.unsupportedPlatform => '当前平台不支持保存图片',
      ReaderImageExportFailureReason.unsupportedFormat => '当前图片格式不支持保存',
      ReaderImageExportFailureReason.mediaWriteFailed || null => '保存图片失败，请重试',
    };
  }

  Future<void> _showDisplaySettingsSheet() async {
    _overlayController.hideMenu();
    final preferences =
        ref.read(readerPreferencesControllerProvider).value ??
        ReaderPreferences.defaults();
    final controller = ref.read(readerPreferencesControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ReaderDisplaySettingsSheet(
        preferences: preferences,
        onModeChanged: (mode) => unawaited(_onReaderModeChanged(mode)),
        onPageFitChanged: (value) => unawaited(controller.setPageFit(value)),
        onBackgroundChanged: (value) =>
            unawaited(controller.setBackground(value)),
        onPageSpacingChanged: (value) =>
            unawaited(controller.setPageSpacing(value)),
        onShowPageIndicatorChanged: (value) =>
            unawaited(controller.setShowPageIndicator(value)),
      ),
    );
  }

  Future<void> _showModeSheet() async {
    _overlayController.hideMenu();
    final currentMode =
        ref.read(readerPreferencesControllerProvider).value?.readerMode ??
        ReaderPreferences.defaults().readerMode;
    final selected = await showModalBottomSheet<ReaderModePreference>(
      context: context,
      showDragHandle: true,
      builder: (context) => ReaderModeSheet(currentMode: currentMode),
    );
    if (selected == null || !mounted) {
      return;
    }
    await _onReaderModeChanged(selected);
  }

  Future<void> _onReaderModeChanged(ReaderModePreference nextMode) async {
    final currentMode =
        ref.read(readerPreferencesControllerProvider).value?.readerMode ??
        ReaderPreferences.defaults().readerMode;
    if (currentMode == nextMode) {
      return;
    }
    if (currentMode == ReaderModePreference.vertical) {
      _verticalPositionDriver.cancelActive(
        ReaderVerticalSeekCancelReason.modeChanged,
      );
    }
    final positionState = _positionState;
    if (positionState == null) {
      return;
    }
    final targetIndex = positionState.committedLogicalIndex;
    final itemCount = _capability.content.length;
    await ref
        .read(readerPreferencesControllerProvider.notifier)
        .setReaderMode(nextMode);
    if (!mounted || !_isCurrentPositionState(positionState, itemCount)) {
      return;
    }
    positionState.consumeInitialRestore();
    final pendingPagedSeek = positionState.pendingPagedSeek;
    if (pendingPagedSeek != null) {
      positionState.clearPendingPagedSeek(pendingPagedSeek);
    }
    _commitLogicalIndex(targetIndex);
    _setZoomGate(false, paged: false);
    _activePagedIndex.value = targetIndex;
    if (nextMode == ReaderModePreference.vertical) {
      _pageController?.dispose();
      _pageController = null;
      _pageControllerOwnerId = null;
    }
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_isCurrentPositionState(positionState, itemCount)) {
      return;
    }

    final generation = ++_seekGeneration;
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.seekStarted,
      index: targetIndex,
      mode: nextMode,
      generation: generation,
      targetIndex: targetIndex,
      status: 'modeSwitch',
      result: 'pending',
    );
    if (nextMode == ReaderModePreference.vertical) {
      final verticalResult = await _jumpVerticalToIndex(targetIndex);
      _performanceMetrics.recordSeek(
        elapsed: verticalResult.elapsed,
        correctionDelta: verticalResult.correctionDelta,
      );
      if (verticalResult.status == ReaderVerticalSeekStatus.cancelled) {
        _recordSeekSuperseded(
          seekGeneration: generation,
          targetIndex: targetIndex,
          mode: nextMode,
          reason: verticalResult.cancelReason?.name ?? 'cancelled',
          elapsedMs: verticalResult.elapsed.inMilliseconds,
          correctionDelta: verticalResult.correctionDelta,
        );
        _scheduleVerticalProgressSync();
        return;
      }
      if (!verticalResult.reached) {
        _recordReaderDiagnostic(
          type: ContinuousImageDiagnosticEventType.seekFailed,
          index: _lastKnownIndex,
          mode: nextMode,
          generation: generation,
          targetIndex: targetIndex,
          status: 'modeSwitch',
          result: 'verticalSeekUnavailable',
          elapsedMs: verticalResult.elapsed.inMilliseconds,
          correctionDelta: verticalResult.correctionDelta,
        );
        return;
      }
      if (!_isCurrentPositionState(positionState, itemCount)) {
        return;
      }
      _commitLogicalIndex(targetIndex);
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekReached,
        index: targetIndex,
        mode: nextMode,
        generation: generation,
        targetIndex: targetIndex,
        status: 'modeSwitch',
        result: 'reached',
        elapsedMs: verticalResult.elapsed.inMilliseconds,
        correctionDelta: verticalResult.correctionDelta,
      );
      return;
    }
    _queueOrApplyPagedSeek(
      content: _capability.content,
      positionState: positionState,
      targetIndex: targetIndex,
      generation: generation,
      recordReached: true,
    );
  }

  ContinuousImageReaderMode _readerMode(ReaderPreferences preferences) {
    return preferences.readerMode == ReaderModePreference.vertical
        ? ContinuousImageReaderMode.vertical
        : ContinuousImageReaderMode.horizontal;
  }

  ReaderTopBarConfig _buildTopBar(ReaderEngineContext context) {
    final title = _capability.titleFor(context);
    return ReaderTopBarConfig(
      title: title.title,
      subtitle: title.subtitle,
      onBack: () => unawaited(_popReader(_capability.exitResult)),
      onTitleTap: () => unawaited(_popReader(_capability.exitResult)),
      actions: _withMenuDismiss(_capability.topActions(context)),
    );
  }

  ReaderBottomBarConfig _buildBottomBar(
    ReaderEngineContext context,
    ReaderPreferences preferences,
  ) {
    final total = context.totalCount;
    final currentIndex = _sliderPreviewIndex ?? _lastKnownIndex;
    final nav = _capability.chapterNav(context);
    return ReaderBottomBarConfig(
      progress: ReaderProgressConfig.discrete(
        current: currentIndex + 1,
        total: total,
        previousTooltip: nav?.previousTooltip ?? '上一章',
        nextTooltip: nav?.nextTooltip ?? '下一章',
        nextIcon: nav?.nextIcon ?? Icons.skip_next,
        previousEnabled: nav?.hasPrevious ?? false,
        nextEnabled: nav?.hasNext ?? false,
        interactionLocked: _isSliderCommitInFlight,
        onPrevious: nav?.onPrevious,
        onNext: nav?.onNext,
        onChangeStart: (value) => _onProgressChangeStart(value, total),
        onChanged: (value) => _onProgressChanged(value, total),
        onChangeEnd: (value) => _onProgressChangeEnd(
          sliderValue: value,
          preferences: preferences,
          total: total,
        ),
      ),
      actions: _withMenuDismiss(_capability.bottomActions(context)),
    );
  }

  /// 按动作策略收起 overlay 菜单。
  ///
  /// 默认动作会关闭菜单；模式轮询等需要连续操作的动作可以显式保留菜单。
  List<ReaderToolbarAction> _withMenuDismiss(
    List<ReaderToolbarAction> actions,
  ) {
    return actions
        .map(
          (action) => ReaderToolbarAction(
            id: action.id,
            icon: action.icon,
            label: action.label,
            enabled: action.enabled,
            dismissMenu: action.dismissMenu,
            onPressed: () {
              if (action.dismissMenu) {
                _overlayController.hideMenu();
              }
              action.onPressed();
            },
          ),
        )
        .toList(growable: false);
  }

  Future<void> _popReader([Object? result]) async {
    if (!_exitFlushed) {
      _exitFlushed = true;
      await _capability.onExit();
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
  }

  Widget _buildContentLayer({
    required BuildContext context,
    required ReaderContent content,
    required ContinuousImageReaderMode mode,
    required ReaderPreferences preferences,
    required ReaderEngineContext engineContext,
  }) {
    final background = _backgroundColor(preferences);
    final chromePalette = const ReaderChromePaletteResolver().resolve(
      Theme.of(context),
    );
    final hint = _capability.topHint(engineContext);
    return Column(
      children: [
        if (hint != null)
          Container(
            width: double.infinity,
            color: chromePalette.chromeBackground,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: chromePalette.onChromeVariant,
              ),
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: background,
            child: mode == ContinuousImageReaderMode.vertical
                ? _buildVertical(content, preferences, engineContext)
                : _buildPaged(content, preferences),
          ),
        ),
      ],
    );
  }

  void _onOverlayVisibilityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onVerticalReaderZoomStateChanged(bool isZoomed) {
    if (_zoomGate.value == isZoomed) {
      return;
    }
    _setZoomGate(isZoomed, paged: false);
    _recordReaderDiagnostic(
      type: isZoomed
          ? ContinuousImageDiagnosticEventType.zoomActivated
          : ContinuousImageDiagnosticEventType.zoomDeactivated,
      index: _lastKnownIndex,
      mode: ReaderModePreference.vertical,
      status: isZoomed ? 'active' : 'inactive',
      result: isZoomed ? 'zoomed' : 'resting',
    );
  }

  void _onPagedImageZoomStateChanged(int imageIndex, bool isZoomed) {
    if (_activePagedIndex.value != imageIndex || _zoomGate.value == isZoomed) {
      return;
    }
    _setZoomGate(isZoomed, paged: true);
    _recordReaderDiagnostic(
      type: isZoomed
          ? ContinuousImageDiagnosticEventType.zoomActivated
          : ContinuousImageDiagnosticEventType.zoomDeactivated,
      index: imageIndex,
      status: isZoomed ? 'active' : 'inactive',
      result: isZoomed ? 'zoomed' : 'resting',
    );
  }

  void _setZoomGate(bool isZoomed, {required bool paged}) {
    if (paged && isZoomed) {
      _holdPagedScrollForZoom();
    } else {
      _releasePagedZoomScrollHold();
    }
    _zoomGate.value = isZoomed;
  }

  void _holdPagedScrollForZoom() {
    final controller = _pageController;
    if (_pagedZoomScrollHold != null ||
        controller == null ||
        !controller.hasClients) {
      return;
    }
    _pagedZoomScrollHold = controller.position.hold(() {
      _pagedZoomScrollHold = null;
    });
  }

  void _releasePagedZoomScrollHold() {
    final hold = _pagedZoomScrollHold;
    _pagedZoomScrollHold = null;
    hold?.cancel();
  }

  void _hideReaderMenuForContentMotion() {
    if (!_overlayController.isMenuVisible || _isSliderCommitInFlight) {
      return;
    }
    _overlayController.hideMenu();
  }

  void _pulsePageIndicator() {
    _pageIndicatorDimTimer?.cancel();
    if (mounted) {
      setState(() {
        _isPageIndicatorHighlighted = true;
      });
    }
    _pageIndicatorDimTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPageIndicatorHighlighted = false;
      });
    });
  }

  void _recordReaderDiagnostic({
    required ContinuousImageDiagnosticEventType type,
    String? ownerId,
    String? itemId,
    int? index,
    String? source,
    ReaderModePreference? mode,
    int? generation,
    int? targetIndex,
    String? status,
    String? result,
    String? preloadKind,
    bool? applied,
    int? elapsedMs,
    double? correctionDelta,
    String message = '',
  }) {
    final recorder = _capability.diagnosticRecorder;
    if (!recorder.enabled) {
      return;
    }
    final content = _capability.content;
    final logicalIndex = index ?? _lastKnownIndex;
    final resolvedItemId =
        itemId ??
        (logicalIndex >= 0 && logicalIndex < content.items.length
            ? content.items[logicalIndex].id
            : '-');
    try {
      recorder.recordContinuousImage(
        ContinuousImageDiagnosticEvent(
          time: DateTime.now(),
          type: type,
          itemId: resolvedItemId,
          ownerId: ownerId ?? content.ownerId,
          index: logicalIndex,
          source: source,
          readerKind: _capability.readerKind.name,
          mode: (mode ?? _diagnosticMode).name,
          generation: generation,
          targetIndex: targetIndex,
          status: status,
          result: result,
          preloadKind: preloadKind,
          applied: applied,
          elapsedMs: elapsedMs,
          correctionDelta: correctionDelta,
          message: message,
        ),
      );
    } catch (_) {
      // Diagnostics must never alter reader interaction or cache behavior.
    }
  }
}

class _ReaderVerticalTrailingSpec {
  const _ReaderVerticalTrailingSpec({
    this.builder,
    this.itemCount = 0,
    this.indexedBuilder,
  });

  const _ReaderVerticalTrailingSpec.single(WidgetBuilder? builder)
    : this(builder: builder, itemCount: builder == null ? 0 : 1);

  final WidgetBuilder? builder;
  final int itemCount;
  final IndexedWidgetBuilder? indexedBuilder;
}
