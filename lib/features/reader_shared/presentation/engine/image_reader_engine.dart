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

  bool _isPageIndicatorHighlighted = false;
  Timer? _pageIndicatorDimTimer;

  // 逐图缩放标记，用于协调 page/scroll 手势，而不把手势逻辑耦合进图片渲染。
  final Map<int, bool> _zoomedStateByIndex = <int, bool>{};
  final Set<int> _reportedVisibleImageIndexes = <int>{};

  String? _lastVerticalRestoreKey;
  String? _lastPagedRestoreKey;
  String? _lastOwnerId;
  bool _exitFlushed = false;

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
      ReaderImageSessionPreloadCoordinator(onResult: _recordSessionPreload);

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

    if (content.isEmpty) {
      return const Scaffold(body: Center(child: Text('没有可阅读图片')));
    }

    _resetIfOwnerChanged(content.ownerId);
    _syncPageControllerIfNeeded(mode, content.initialIndex);
    _restorePositionIfNeeded(mode, content);

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
            tapZonesEnabled: !_isAnyImageZoomed,
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
    return ContinuousImageReaderView(
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
      horizontalPhysics: _isAnyImageZoomed
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
    return ReaderZoomableImage(
      onZoomStateChanged: (isZoomed) =>
          _onImageZoomStateChanged(index, isZoomed),
      child: _capability.buildImageContent(
        context,
        ReaderImageBuildSpec(
          item: item,
          index: index,
          paged: paged,
          fit: _imageFitFor(preferences.pageFit, paged: paged),
        ),
      ),
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

  void _resetIfOwnerChanged(String ownerId) {
    if (_lastOwnerId == ownerId) {
      return;
    }
    final previous = _lastOwnerId;
    if (previous != null) {
      _extentRegistry.clearForOwner(previous);
    }
    _lastOwnerId = ownerId;
    _latestItems = const <ContinuousImageItem>[];
    _pendingScrollCompensationDelta = 0;
    _lastVerticalRestoreKey = null;
    _lastPagedRestoreKey = null;
    _reportedVisibleImageIndexes.clear();
    _zoomedStateByIndex.clear();
    _lastKnownIndex = _capability.content.initialIndex;
    _sessionPreloadCoordinator.resetSession();
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
    ReaderContent content,
  ) {
    if (_isSliderCommitInFlight) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSliderCommitInFlight) {
        return;
      }
      if (mode == ContinuousImageReaderMode.vertical) {
        _restoreVertical(content);
        return;
      }
      _restorePaged(content);
    });
  }

  void _restoreVertical(ReaderContent content) {
    final restoreKey = '${content.ownerId}:vertical';
    if (_lastVerticalRestoreKey == restoreKey) {
      return;
    }
    final targetOffset = _capability.initialVerticalScrollOffset;
    if (_scrollController.hasClients &&
        _scrollController.offset == 0 &&
        targetOffset != null &&
        targetOffset > 0) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        final offset = targetOffset.clamp(0.0, maxScroll).toDouble();
        if (offset > 0) {
          _scrollController.jumpTo(offset);
        }
      }
    }
    _lastVerticalRestoreKey = restoreKey;
  }

  void _restorePaged(ReaderContent content) {
    final restoreKey = '${content.ownerId}:paged:${content.initialIndex}';
    if (_lastPagedRestoreKey == restoreKey) {
      return;
    }
    _lastPagedRestoreKey = restoreKey;
    final pageController = _pageController;
    if (pageController == null || !pageController.hasClients) {
      return;
    }
    if (pageController.position.isScrollingNotifier.value) {
      return;
    }
    final targetPage = content.initialIndex;
    final page = pageController.page;
    if (page != null && (page - targetPage).abs() < 0.01) {
      return;
    }
    final currentPage = page?.round() ?? pageController.initialPage;
    if (currentPage != targetPage) {
      pageController.jumpToPage(targetPage);
    }
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
      _lastKnownIndex = index;
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
    _lastKnownIndex = pageIndex;
    _reportedVisibleImageIndexes.add(pageIndex);
    _capability.onScrollProgress(index: pageIndex, offset: 0);
    _submitSessionPreloadWindow(
      focusIndex: pageIndex,
      scrollDirection: pageIndex < previousIndex
          ? ContinuousImageScrollDirection.reverse
          : ContinuousImageScrollDirection.forward,
    );
    _tryReleaseSliderCommitLock(pageIndex);
    if (mounted) {
      setState(() {});
    }
  }

  void _turnPageByTap({
    required ReaderModePreference mode,
    required int total,
    required bool isLeftTap,
  }) {
    if (_isAnyImageZoomed) {
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
  }

  void _onProgressChanged(double sliderValue, int total) {
    final index = sliderValue.round().clamp(0, total - 1).toInt();
    setState(() => _sliderPreviewIndex = index);
  }

  Future<void> _onProgressChangeEnd({
    required double sliderValue,
    required ReaderPreferences preferences,
    required int total,
  }) async {
    final now = DateTime.now();
    if (_lastSliderCommitAt != null &&
        now.difference(_lastSliderCommitAt!) <
            const Duration(milliseconds: 120)) {
      return;
    }
    _lastSliderCommitAt = now;
    final targetIndex = sliderValue.round().clamp(0, total - 1).toInt();
    final previousIndex = _lastKnownIndex;
    _pulsePageIndicator();

    setState(() {
      _isSliderCommitInFlight = true;
      _pendingCommittedIndex = targetIndex;
      _sliderPreviewIndex = targetIndex;
      _lastKnownIndex = targetIndex;
    });
    _lastVerticalRestoreKey = null;
    _lastPagedRestoreKey = null;

    if (preferences.readerMode == ReaderModePreference.vertical) {
      await _jumpVerticalToIndex(targetIndex);
      _submitSessionPreloadWindow(
        focusIndex: targetIndex,
        scrollDirection: targetIndex < previousIndex
            ? ContinuousImageScrollDirection.reverse
            : ContinuousImageScrollDirection.forward,
      );
      await _capability.onSeek(
        index: targetIndex,
        offset: _scrollController.hasClients ? _scrollController.offset : 0,
      );
      _tryReleaseSliderCommitLock(targetIndex);
      return;
    }

    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      _submitSessionPreloadWindow(
        focusIndex: targetIndex,
        scrollDirection: targetIndex < previousIndex
            ? ContinuousImageScrollDirection.reverse
            : ContinuousImageScrollDirection.forward,
      );
      pageController.jumpToPage(targetIndex);
    }
    await _capability.onSeek(index: targetIndex, offset: 0);
    _tryReleaseSliderCommitLock(targetIndex);
  }

  void _tryReleaseSliderCommitLock(int reachedIndex) {
    if (!_isSliderCommitInFlight ||
        _pendingCommittedIndex != reachedIndex ||
        !mounted) {
      return;
    }
    setState(() {
      _isSliderCommitInFlight = false;
      _pendingCommittedIndex = null;
      _sliderPreviewIndex = null;
    });
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

  void _recordSessionPreload(ReaderImageSessionPreloadResult result) {
    final recorder = _capability.diagnosticRecorder;
    if (!recorder.enabled) {
      return;
    }
    recorder.recordContinuousImage(
      ContinuousImageDiagnosticEvent(
        time: DateTime.now(),
        type: ContinuousImageDiagnosticEventType.prefetchCompleted,
        itemId: result.spec.cacheKey ?? result.spec.sourceUrl,
        ownerId: _capability.content.ownerId,
        index: result.spec.imageIndex ?? -1,
        source: result.spec.sourceUrl,
        message:
            'sessionPreload kind=${result.kind.name} '
            'success=${result.result.success} '
            'applied=${result.applied} '
            'diskAttempted=${result.result.diskCacheAttempted} '
            'diskHit=${result.result.fromDiskCache} '
            'decodeAttempted=${result.result.decodePrecacheAttempted} '
            'decoded=${result.result.decoded} '
            'reason=${result.result.failureReason ?? '-'}',
      ),
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
    final targetIndex = _lastKnownIndex;
    await ref
        .read(readerPreferencesControllerProvider.notifier)
        .setReaderMode(nextMode);
    if (!mounted) {
      return;
    }
    _lastVerticalRestoreKey = null;
    _lastPagedRestoreKey = null;
    _lastKnownIndex = targetIndex;
    if (nextMode == ReaderModePreference.vertical) {
      _pageController?.dispose();
      _pageController = null;
    }
    if (mounted) {
      setState(() {});
    }
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

  bool get _isAnyImageZoomed =>
      _zoomedStateByIndex.values.any((isZoomed) => isZoomed);

  void _onOverlayVisibilityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onImageZoomStateChanged(int imageIndex, bool isZoomed) {
    final current = _zoomedStateByIndex[imageIndex] ?? false;
    if (current == isZoomed) {
      return;
    }
    setState(() {
      if (isZoomed) {
        _zoomedStateByIndex[imageIndex] = true;
      } else {
        _zoomedStateByIndex.remove(imageIndex);
      }
    });
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
}
