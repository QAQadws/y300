import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_display_settings_sheet.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_page_indicator_overlay.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_position_state.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_preload_coordinator.dart';

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
  late final ReaderOverlayController _overlayController;

  int _lastKnownIndex = 0;

  // 滑块拖动会话 + commit 锁状态机（迁移自 ComicReaderPage）。
  int? _sliderPreviewIndex;
  DateTime? _lastSliderCommitAt;
  bool _isSliderCommitInFlight = false;
  int? _pendingCommittedIndex;
  int? _activeSeekGeneration;

  bool _isPageIndicatorHighlighted = false;
  Timer? _pageIndicatorDimTimer;

  // 纵向模式缩放整条连续图片流；分页模式才按当前图片记录缩放状态。
  bool _isVerticalReaderZoomed = false;
  final Map<int, bool> _pagedZoomedStateByIndex = <int, bool>{};
  final Set<int> _reportedVisibleImageIndexes = <int>{};

  String? _lastOwnerId;
  ReaderPositionState? _positionState;
  bool _exitFlushed = false;

  // These counters are diagnostic-only. Position and preload behavior must
  // remain independent from observability state.
  int _readerSessionGeneration = 0;
  int _restoreGeneration = 0;
  int _seekGeneration = 0;
  ReaderModePreference _diagnosticMode = ReaderModePreference.vertical;
  bool _positionRetryScheduled = false;

  // 连续图片高度/锚定基础设施（迁移自 ComicReaderPage）。
  static const ContinuousImageLayoutResolver _layoutResolver =
      ContinuousImageLayoutResolver();
  static const ContinuousImageViewportTracker _viewportTracker =
      ContinuousImageViewportTracker(layoutResolver: _layoutResolver);
  static const ContinuousImageScrollAnchorCoordinator _anchorCoordinator =
      ContinuousImageScrollAnchorCoordinator(layoutResolver: _layoutResolver);
  final InMemoryContinuousImageExtentRegistry _extentRegistry =
      InMemoryContinuousImageExtentRegistry();
  late final ReaderImageSessionPreloadCoordinator _sessionPreloadCoordinator =
      ReaderImageSessionPreloadCoordinator(
        onScheduled: _recordSessionPreloadScheduled,
        onResult: _recordSessionPreload,
      );

  List<ContinuousImageItem> _latestItems = const <ContinuousImageItem>[];
  double _pendingScrollCompensationDelta = 0;
  ScrollPosition? _observedScrollPosition;

  ReaderCapability get _capability => widget.capability;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onVerticalScroll);
    _overlayController = ReaderOverlayController()
      ..addListener(_onOverlayVisibilityChanged);
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
    _pageController?.dispose();
    _overlayController
      ..removeListener(_onOverlayVisibilityChanged)
      ..dispose();
    _pageIndicatorDimTimer?.cancel();
    _sessionPreloadCoordinator.dispose();
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
    _syncPageControllerIfNeeded(mode, positionState.committedLogicalIndex);
    _restorePositionIfNeeded(mode, preferences.readerMode, content);

    final total = content.length;
    final engineContext = _engineContext(preferences, total);

    return Scaffold(
      body: Stack(
        children: [
          ReaderOverlayScaffold(
            controller: _overlayController,
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
            tapZonesEnabled: !_isAnyReaderZoomed,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncScrollPositionActivityListener();
        _submitSessionPreloadWindow(
          focusIndex: _lastKnownIndex,
          scrollDirection: ContinuousImageScrollDirection.idle,
        );
      }
    });
    final reader = ContinuousImageReaderView(
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
      verticalTrailingBuilder: _capability.verticalTrailingBuilder(
        engineContext,
      ),
      itemBuilder: (context, item, index, {required paged}) {
        return _buildImage(item, index, preferences, paged: false);
      },
    );
    return ReaderZoomableImage(
      key: const Key('image-reader-engine-vertical-zoom-surface'),
      behavior: ReaderZoomBehavior.continuousVertical,
      onZoomStateChanged: _onVerticalReaderZoomStateChanged,
      child: reader,
    );
  }

  Widget _buildPaged(ReaderContent content, ReaderPreferences preferences) {
    final items = content.items;
    _latestItems = items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precachePagedWindow(_lastKnownIndex);
      }
    });
    return ContinuousImageReaderView(
      items: items,
      mode: ContinuousImageReaderMode.horizontal,
      pageController: _pageController,
      horizontalPhysics: _isPagedImageZoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      reverse: preferences.readerMode == ReaderModePreference.rtl,
      onPageChanged: _onPageChanged,
      horizontalPageKey: widget.pageKey,
      horizontalPagePadding: EdgeInsets.all(
        preferences.pageSpacing.clamp(0.0, 48.0).toDouble(),
      ),
      layoutResolver: _layoutResolver,
      onExtentResolved: _recordExtent,
      itemBuilder: (context, item, index, {required paged}) {
        return _buildImage(item, index, preferences, paged: true);
      },
    );
  }

  Widget _buildImage(
    ContinuousImageItem item,
    int index,
    ReaderPreferences preferences, {
    required bool paged,
  }) {
    _notifyCurrentImageVisible(index);
    final image = _capability.buildImageContent(
      context,
      ReaderImageBuildSpec(
        item: item,
        index: index,
        paged: paged,
        fit: _imageFitFor(preferences.pageFit, paged: paged),
      ),
    );
    if (!paged) {
      return image;
    }
    return ReaderZoomableImage(
      onZoomStateChanged: (isZoomed) =>
          _onPagedImageZoomStateChanged(index, isZoomed),
      child: image,
    );
  }

  BoxFit _imageFitFor(ReaderPageFitPreference fit, {required bool paged}) {
    switch (fit) {
      case ReaderPageFitPreference.fitWidth:
        return paged ? BoxFit.contain : BoxFit.fitWidth;
      case ReaderPageFitPreference.fitHeight:
        return BoxFit.fitHeight;
      case ReaderPageFitPreference.contain:
        return BoxFit.contain;
      case ReaderPageFitPreference.original:
        return BoxFit.none;
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
    if (previous != null) {
      _extentRegistry.clearForOwner(previous);
    }
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
    _isVerticalReaderZoomed = false;
    _pagedZoomedStateByIndex.clear();
    _lastKnownIndex = initialIndex;
    _isSliderCommitInFlight = false;
    _pendingCommittedIndex = null;
    _activeSeekGeneration = null;
    _sliderPreviewIndex = null;
    _lastSliderCommitAt = null;
    _positionRetryScheduled = false;
    _sessionPreloadCoordinator.resetSession();
    _readerSessionGeneration += 1;
    _restoreGeneration = 0;
    _seekGeneration = 0;
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.readerSessionCreated,
      index: _lastKnownIndex,
      mode: readerMode,
      generation: _readerSessionGeneration,
      status: 'created',
      result: 'ready',
    );
    return next;
  }

  void _syncPageControllerIfNeeded(
    ContinuousImageReaderMode mode,
    int initialIndex,
  ) {
    if (mode == ContinuousImageReaderMode.vertical) {
      return;
    }
    final expectedInitialPage = initialIndex.clamp(0, 1 << 20).toInt();
    final controller = _pageController;
    if (controller == null) {
      _pageController = PageController(initialPage: expectedInitialPage);
      return;
    }
    if (!controller.hasClients &&
        controller.initialPage != expectedInitialPage) {
      controller.dispose();
      _pageController = PageController(initialPage: expectedInitialPage);
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
      positionState.consumeInitialRestore();
      _commitLogicalIndex(
        pageController.page?.round() ?? positionState.committedLogicalIndex,
      );
      _recordInitialRestoreCompleted(
        index: _lastKnownIndex,
        mode: readerMode,
        generation: generation,
        status: 'consumed',
        result: 'scrollInProgress',
      );
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
  }) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.initialRestoreCompleted,
      index: index,
      mode: mode,
      generation: generation,
      targetIndex: index,
      status: status,
      result: result,
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
    final ratio = (position.pixels / position.maxScrollExtent)
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

  void _notifyCurrentImageVisible(int imageIndex) {
    if (_reportedVisibleImageIndexes.contains(imageIndex)) {
      return;
    }
    _reportedVisibleImageIndexes.add(imageIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _capability.onImageVisible(imageIndex);
    });
  }

  // --- paged turning + page change ---

  Future<void> _onPageChanged(int pageIndex) async {
    if (pageIndex == _lastKnownIndex) {
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
    _reportedVisibleImageIndexes.add(pageIndex);
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

  void _turnPageByTap({
    required ReaderModePreference mode,
    required int total,
    required bool isLeftTap,
  }) {
    if (_isPagedImageZoomed) {
      return;
    }
    final pageController = _pageController;
    if (pageController == null || !pageController.hasClients) {
      return;
    }
    final current = pageController.page?.round() ?? _lastKnownIndex;
    final isRtl = mode == ReaderModePreference.rtl;
    final isPreviousAction = isRtl ? !isLeftTap : isLeftTap;
    final delta = isPreviousAction ? -1 : 1;
    final target = (current + delta).clamp(0, total - 1).toInt();
    if (target == current) {
      return;
    }
    _submitSessionPreloadWindow(
      focusIndex: target,
      scrollDirection: delta < 0
          ? ContinuousImageScrollDirection.reverse
          : ContinuousImageScrollDirection.forward,
    );
    pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
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
      _lastKnownIndex = targetIndex;
    });

    try {
      var reached = false;
      if (preferences.readerMode == ReaderModePreference.vertical) {
        await _jumpVerticalToIndex(targetIndex);
        if (!_isCurrentPositionState(positionState, total)) {
          _recordSeekSuperseded(
            seekGeneration: seekGeneration,
            targetIndex: targetIndex,
            mode: preferences.readerMode,
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
      }

      _submitSessionPreloadWindow(
        focusIndex: targetIndex,
        scrollDirection: targetIndex < previousIndex
            ? ContinuousImageScrollDirection.reverse
            : ContinuousImageScrollDirection.forward,
      );
      if (!_isCurrentPositionState(positionState, total)) {
        _recordSeekSuperseded(
          seekGeneration: seekGeneration,
          targetIndex: targetIndex,
          mode: preferences.readerMode,
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
      _recordReaderDiagnostic(
        type: ContinuousImageDiagnosticEventType.seekFailed,
        index: _lastKnownIndex,
        mode: preferences.readerMode,
        generation: seekGeneration,
        targetIndex: targetIndex,
        status: 'failed',
        result: error.runtimeType.toString(),
      );
    } finally {
      _releaseSliderCommitLock(seekGeneration);
    }
  }

  void _recordSeekSuperseded({
    required int seekGeneration,
    required int targetIndex,
    required ReaderModePreference mode,
  }) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.seekSuperseded,
      index: _lastKnownIndex,
      mode: mode,
      generation: seekGeneration,
      targetIndex: targetIndex,
      status: 'superseded',
      result: 'ownerOrItemCountChanged',
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
    } else {
      release();
    }
  }

  Future<void> _jumpVerticalToIndex(int targetIndex) async {
    final items = _latestItems;
    final totalImages = items.length;
    if (!_scrollController.hasClients || totalImages <= 1) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }
    final crossAxisExtent = MediaQuery.sizeOf(context).width;
    final estimatedOffset = _extentRegistry.estimateOffsetForIndex(
      targetIndex,
      items,
      crossAxisExtent: crossAxisExtent,
      resolver: _layoutResolver,
    );
    final ratio = targetIndex / (totalImages - 1);
    final fallbackOffset = maxScroll * ratio;
    final offset =
        (estimatedOffset.isFinite && estimatedOffset > 0
                ? estimatedOffset
                : fallbackOffset)
            .clamp(0.0, maxScroll)
            .toDouble();
    _scrollController.jumpTo(offset);
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollController.hasClients) {
      return;
    }
    final latestMax = _scrollController.position.maxScrollExtent;
    final latestEstimatedOffset = _extentRegistry.estimateOffsetForIndex(
      targetIndex,
      items,
      crossAxisExtent: crossAxisExtent,
      resolver: _layoutResolver,
    );
    final correctedOffset =
        (latestEstimatedOffset.isFinite && latestEstimatedOffset > 0
                ? latestEstimatedOffset
                : latestMax * ratio)
            .clamp(0.0, latestMax)
            .toDouble();
    if ((_scrollController.offset - correctedOffset).abs() > 1.5) {
      _scrollController.jumpTo(correctedOffset);
    }
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

  Size? _expectedPreloadDisplaySize() {
    if (!mounted) {
      return null;
    }
    final mediaSize = MediaQuery.maybeSizeOf(context);
    if (mediaSize == null || mediaSize.width <= 0) {
      return null;
    }
    return Size(mediaSize.width, mediaSize.height);
  }

  void _recordSessionPreloadScheduled(
    ReaderImageSessionPreloadScheduled scheduled,
  ) {
    _recordReaderDiagnostic(
      type: ContinuousImageDiagnosticEventType.prefetchScheduled,
      ownerId: scheduled.readerOwnerId,
      itemId: scheduled.spec.cacheKey ?? scheduled.spec.sourceUrl,
      index: scheduled.spec.imageIndex ?? -1,
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
      itemId: result.spec.cacheKey ?? result.spec.sourceUrl,
      index: result.spec.imageIndex ?? -1,
      source: result.spec.sourceUrl,
      generation: result.generation,
      status: 'completed',
      result: result.result.success ? 'success' : 'failure',
      preloadKind: result.kind.name,
      applied: result.applied,
      message:
          'diskAttempted=${result.result.diskCacheAttempted} '
          'diskHit=${result.result.fromDiskCache} '
          'decodeAttempted=${result.result.decodePrecacheAttempted} '
          'decoded=${result.result.decoded} '
          'reason=${result.result.failureReason ?? '-'}',
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
        ReaderModePreference.vertical;
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
        ReaderModePreference.vertical;
    if (currentMode == nextMode) {
      return;
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
    _isVerticalReaderZoomed = false;
    _pagedZoomedStateByIndex.clear();
    if (nextMode == ReaderModePreference.vertical) {
      _pageController?.dispose();
      _pageController = null;
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
      await _jumpVerticalToIndex(targetIndex);
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
      progress: ReaderProgressConfig(
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

  /// 工具栏动作执行前先收起 overlay 菜单——对齐原漫画各 handler 的行为，
  /// 也让抽屉打开时不与顶部/底部栏叠加。引擎内置动作（显示/模式）自身已收起，
  /// 这里对能力注入的动作统一补齐。
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
            onPressed: () {
              _overlayController.hideMenu();
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

  bool get _isPagedImageZoomed =>
      _pagedZoomedStateByIndex.values.any((isZoomed) => isZoomed);

  bool get _isAnyReaderZoomed => _isVerticalReaderZoomed || _isPagedImageZoomed;

  void _onOverlayVisibilityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onVerticalReaderZoomStateChanged(bool isZoomed) {
    if (_isVerticalReaderZoomed == isZoomed) {
      return;
    }
    setState(() {
      _isVerticalReaderZoomed = isZoomed;
    });
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
    final current = _pagedZoomedStateByIndex[imageIndex] ?? false;
    if (current == isZoomed) {
      return;
    }
    setState(() {
      if (isZoomed) {
        _pagedZoomedStateByIndex[imageIndex] = true;
      } else {
        _pagedZoomedStateByIndex.remove(imageIndex);
      }
    });
    _recordReaderDiagnostic(
      type: isZoomed
          ? ContinuousImageDiagnosticEventType.zoomActivated
          : ContinuousImageDiagnosticEventType.zoomDeactivated,
      index: imageIndex,
      status: isZoomed ? 'active' : 'inactive',
      result: isZoomed ? 'zoomed' : 'resting',
    );
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
          message: message,
        ),
      );
    } catch (_) {
      // Diagnostics must never alter reader interaction or cache behavior.
    }
  }
}
