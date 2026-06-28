import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/comic/domain/models/comic_reader_exit_result.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_unavailable.dart';
import 'package:y300/features/comic/domain/services/comic_reader_chapter_preload.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/providers/reader_preferences_provider.dart';
import 'package:y300/features/comic/presentation/services/comic_reader_continuous_image_adapter.dart';
import 'package:y300/features/comic/presentation/widgets/reader_page_indicator_overlay.dart';
import 'package:y300/features/comic/presentation/widgets/reader_zoomable_image.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

enum _ComicReaderMoreAction {
  markReadToggle,
  setCurrentPageAsCover,
  cacheEpisode,
  cacheUnread,
  clearEpisodeCache,
  retryFailedImages,
}

class ComicReaderPage extends ConsumerStatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.comicId,
    required this.episodeId,
  });

  final String comicId;
  final String episodeId;

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage> {
  late final ScrollController _scrollController;
  PageController? _pageController;
  int _lastKnownIndex = 0;

  // Slider session and commit state machine:
  // 1) drag session preview
  // 2) commit lock while applying jump
  // 3) unlock after target sync
  int? _sliderPreviewIndex;
  DateTime? _lastSliderCommitAt;
  bool _isSliderCommitInFlight = false;
  int? _pendingCommittedIndex;

  bool _isPageIndicatorHighlighted = false;
  late final ReaderOverlayController _overlayController;
  final Set<int> _reportedVisibleImageIndexes = <int>{};
  // Keep per-image zoom flags so page-level gestures can be coordinated
  // without coupling gesture logic into image rendering code.
  final Map<int, bool> _zoomedStateByIndex = <int, bool>{};
  ComicReaderController? _lastController;
  bool _exitFlushed = false;
  Timer? _pageIndicatorDimTimer;
  String? _lastPagedRestoreKey;
  String? _lastContinuousImageOwnerId;

  static const ComicReaderContinuousImageAdapter _continuousImageAdapter =
      ComicReaderContinuousImageAdapter();
  static const ContinuousImageLayoutResolver _continuousImageLayoutResolver =
      ContinuousImageLayoutResolver();
  final InMemoryContinuousImageExtentRegistry _imageExtentRegistry =
      InMemoryContinuousImageExtentRegistry();

  ComicReaderArgs get _readerArgs =>
      ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onVerticalScroll);
    _overlayController = ReaderOverlayController()
      ..addListener(_onOverlayVisibilityChanged);
  }

  @override
  void dispose() {
    final controller = _lastController;
    if (!_exitFlushed && controller != null) {
      unawaited(controller.onExitReader());
    }
    _scrollController
      ..removeListener(_onVerticalScroll)
      ..dispose();
    _pageController?.dispose();
    _overlayController
      ..removeListener(_onOverlayVisibilityChanged)
      ..dispose();
    _pageIndicatorDimTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferencesState = ref.watch(readerPreferencesControllerProvider);
    final preferences = preferencesState.value ?? ReaderPreferences.defaults();
    final mode = preferences.readerMode;

    final state = ref.watch(comicReaderControllerProvider(_readerArgs));
    _lastController = ref.read(
      comicReaderControllerProvider(_readerArgs).notifier,
    );
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);

    return Scaffold(
      body: state.when(
        loading: () => _buildReaderLoadingState(preferences),
        error: (error, stackTrace) => _buildReaderErrorState(error),
        data: (viewState) {
          if (viewState.images.isEmpty) {
            return const Center(child: Text('当前章节没有可阅读图片'));
          }

          _resetContinuousImageStateIfNeeded(viewState.episodeId);
          _syncPageControllerIfNeeded(mode, viewState.currentImageIndex);
          _restorePositionIfNeeded(mode, viewState);
          _notifyCurrentImageVisible(viewState.currentImageIndex);

          return Stack(
            children: [
              ReaderOverlayScaffold(
                controller: _overlayController,
                topBar: _buildTopBarConfig(viewState),
                bottomBar: _buildBottomBarConfig(viewState, preferences),
                onLeftTap: mode == ReaderModePreference.vertical
                    ? null
                    : () => _turnPageByTap(
                        mode: mode,
                        viewState: viewState,
                        isLeftTap: true,
                      ),
                onRightTap: mode == ReaderModePreference.vertical
                    ? null
                    : () => _turnPageByTap(
                        mode: mode,
                        viewState: viewState,
                        isLeftTap: false,
                      ),
                bottomSafeFraction: mode == ReaderModePreference.vertical
                    ? 0.2
                    : 0,
                tapZonesEnabled: !_isAnyImageZoomed,
                child: _buildReaderContentLayer(
                  viewState: viewState,
                  mode: mode,
                  preferences: preferences,
                  imageHeaderBuilder: imageHeaderBuilder,
                ),
              ),
              ReaderPageIndicatorOverlay(
                visible:
                    !_overlayController.isMenuVisible &&
                    preferences.showPageIndicator,
                highlighted: _isPageIndicatorHighlighted,
                currentPage: viewState.currentImageIndex + 1,
                totalPages: viewState.images.length,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReaderLoadingState(ReaderPreferences preferences) {
    return _ReaderOpeningPlaceholder(
      background: _readerBackgroundColor(preferences),
    );
  }

  /// 阅读器错误态。
  ///
  /// 拉单话图片失败时（[ComicEpisodeImagesUnavailable]）显示具体根因 + 重
  /// 试按钮——避免和"首楼真无图"混为一谈，也省得用户必须靠"返回再点"
  /// 才能触发新的尝试。
  /// 解析失败（reason == parse）重试无意义，按钮不出。
  Widget _buildReaderErrorState(Object error) {
    final hint = error is ComicEpisodeImagesUnavailable
        ? error.displayHint
        : '加载阅读器失败：$error';
    final retryable =
        error is! ComicEpisodeImagesUnavailable || error.isRetryable;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint, textAlign: TextAlign.center),
            if (retryable) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(comicReaderControllerProvider(_readerArgs)),
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ReaderTopBarConfig _buildTopBarConfig(ComicReaderViewState viewState) {
    return ReaderTopBarConfig(
      title: viewState.comicTitle,
      subtitle: viewState.episodeTitle,
      onBack: () => _popReader(_exitResultFor(viewState)),
      onTitleTap: () => _popReader(_exitResultFor(viewState)),
      actions: [
        ReaderToolbarAction(
          id: 'bookmark',
          icon: viewState.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          label: viewState.isBookmarked ? '取消书签' : '添加书签',
          onPressed: () => _controller().toggleBookmark(),
        ),
        ReaderToolbarAction(
          id: 'open-thread',
          icon: Icons.open_in_new,
          label: '打开原帖',
          onPressed: () => _openSourceThread(viewState),
        ),
        ReaderToolbarAction(
          id: 'more',
          icon: Icons.more_vert,
          label: '更多',
          onPressed: () => unawaited(_showMoreActionSheet(viewState)),
        ),
      ],
    );
  }

  ReaderBottomBarConfig _buildBottomBarConfig(
    ComicReaderViewState viewState,
    ReaderPreferences preferences,
  ) {
    final currentIndex = _sliderPreviewIndex ?? viewState.currentImageIndex;
    final total = viewState.images.length;
    final mode = preferences.readerMode;
    return ReaderBottomBarConfig(
      progress: ReaderProgressConfig(
        current: currentIndex + 1,
        total: total,
        previousTooltip: viewState.hasPreviousEpisode ? '上一话' : '已是第一话',
        nextTooltip: _nextEpisodeTooltip(viewState),
        nextIcon: _nextEpisodeIcon(viewState.nextChapterPreload.status),
        previousEnabled: viewState.hasPreviousEpisode,
        nextEnabled: viewState.hasNextEpisode,
        interactionLocked: _isSliderCommitInFlight,
        onPrevious: () => _openAdjacentEpisode(viewState, previous: true),
        onNext: () => _openAdjacentEpisode(viewState, previous: false),
        onChangeStart: (value) => _onProgressChangeStart(value, total),
        onChanged: (value) => _onProgressChanged(value, total),
        onChangeEnd: (value) => _onProgressChangeEnd(
          sliderValue: value,
          mode: mode,
          viewState: viewState,
          preferences: preferences,
        ),
      ),
      actions: [
        ReaderToolbarAction(
          id: 'mode',
          icon: _modeIcon(mode),
          label: _modeLabel(mode),
          onPressed: () => _showModeSheet(viewState),
        ),
        ReaderToolbarAction(
          id: 'catalog',
          icon: Icons.format_list_bulleted,
          label: '章节',
          onPressed: () => _showChapterListSheet(viewState),
        ),
        ReaderToolbarAction(
          id: 'display',
          icon: Icons.tune,
          label: '显示',
          onPressed: () => _showDisplaySettingsSheet(preferences, viewState),
        ),
        ReaderToolbarAction(
          id: 'cache',
          icon: Icons.download_for_offline_outlined,
          label: '缓存',
          onPressed: () => _controller().cacheCurrentEpisode(),
        ),
      ],
    );
  }

  ComicReaderExitResult _exitResultFor(ComicReaderViewState viewState) {
    return ComicReaderExitResult(
      comicId: viewState.comicId,
      lastReadEpisodeId: viewState.episodeId,
      completedEpisodeIds: viewState.isCurrentEpisodeRead
          ? <String>[viewState.episodeId]
          : const <String>[],
    );
  }

  ComicReaderController _controller() {
    return ref.read(comicReaderControllerProvider(_readerArgs).notifier);
  }

  Future<void> _popReader([Object? result]) async {
    if (!_exitFlushed) {
      _exitFlushed = true;
      await _controller().onExitReader();
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(result);
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
      _controller().onImageVisible(imageIndex);
    });
  }

  Future<void> _onReaderModeChanged(
    ReaderModePreference nextMode,
    ComicReaderViewState viewState,
  ) async {
    final currentMode =
        ref.read(readerPreferencesControllerProvider).value?.readerMode ??
        ReaderModePreference.vertical;
    if (currentMode == nextMode) {
      return;
    }

    final targetIndex = _resolveCurrentLogicalIndex(
      mode: currentMode,
      fallbackIndex: viewState.currentImageIndex,
      maxLength: viewState.images.length,
    );

    await ref
        .read(readerPreferencesControllerProvider.notifier)
        .setReaderMode(nextMode);

    if (!mounted) {
      return;
    }

    await _controller().jumpToImageIndex(targetIndex);

    if (nextMode == ReaderModePreference.vertical) {
      _pageController?.dispose();
      _pageController = null;
    }
  }

  int _resolveCurrentLogicalIndex({
    required ReaderModePreference mode,
    required int fallbackIndex,
    required int maxLength,
  }) {
    final maxIndex = maxLength - 1;
    if (maxIndex < 0) {
      return 0;
    }
    if (mode == ReaderModePreference.vertical) {
      return fallbackIndex.clamp(0, maxIndex).toInt();
    }
    final currentPage = _pageController?.hasClients == true
        ? _pageController!.page?.round()
        : _pageController?.initialPage;
    return (currentPage ?? fallbackIndex).clamp(0, maxIndex).toInt();
  }

  void _syncPageControllerIfNeeded(
    ReaderModePreference mode,
    int initialIndex,
  ) {
    if (mode == ReaderModePreference.vertical) {
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
    ReaderModePreference mode,
    ComicReaderViewState viewState,
  ) {
    if (_isSliderCommitInFlight) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSliderCommitInFlight) {
        return;
      }
      if (mode == ReaderModePreference.vertical) {
        if (_scrollController.hasClients &&
            _scrollController.offset == 0 &&
            viewState.lastScrollOffset > 0) {
          _scrollController.jumpTo(viewState.lastScrollOffset);
        }
        return;
      }

      // PageView owns interactive horizontal scrolling.  Restoring on every
      // rebuild fights the in-flight drag because controller state still
      // points at the previous page until onPageChanged fires.  Deduplicate by
      // episode/mode/page so restoration is only an initial/external sync.
      final restoreKey = _pagedRestoreKey(mode, viewState);
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
      final targetPage = viewState.currentImageIndex;
      final page = pageController.page;
      if (page != null && (page - targetPage).abs() < 0.01) {
        return;
      }
      final currentPage = page?.round() ?? pageController.initialPage;
      if (currentPage != targetPage) {
        pageController.jumpToPage(targetPage);
      }
    });
  }

  String _pagedRestoreKey(
    ReaderModePreference mode,
    ComicReaderViewState viewState,
  ) {
    return '${viewState.episodeId}:${mode.name}:${viewState.currentImageIndex}';
  }

  void _resetContinuousImageStateIfNeeded(String ownerId) {
    if (_lastContinuousImageOwnerId == ownerId) {
      return;
    }
    final previous = _lastContinuousImageOwnerId;
    if (previous != null) {
      _imageExtentRegistry.clearForOwner(previous);
    }
    _lastContinuousImageOwnerId = ownerId;
  }

  void _recordContinuousImageExtent(ContinuousImageExtent extent) {
    _imageExtentRegistry.record(extent);
  }

  IconData _modeIcon(ReaderModePreference mode) {
    switch (mode) {
      case ReaderModePreference.vertical:
        return Icons.view_stream_outlined;
      case ReaderModePreference.ltr:
        return Icons.swipe_left_outlined;
      case ReaderModePreference.rtl:
        return Icons.swipe_right_outlined;
    }
  }

  String _modeLabel(ReaderModePreference mode) {
    switch (mode) {
      case ReaderModePreference.vertical:
        return '垂直';
      case ReaderModePreference.ltr:
        return '左到右';
      case ReaderModePreference.rtl:
        return '右到左';
    }
  }

  IconData _nextEpisodeIcon(ComicReaderChapterPreloadStatus status) {
    switch (status) {
      case ComicReaderChapterPreloadStatus.loadingImages:
      case ComicReaderChapterPreloadStatus.preloadingPages:
        return Icons.downloading_outlined;
      case ComicReaderChapterPreloadStatus.ready:
        return Icons.offline_bolt_outlined;
      case ComicReaderChapterPreloadStatus.failed:
        return Icons.error_outline;
      case ComicReaderChapterPreloadStatus.unavailable:
      case ComicReaderChapterPreloadStatus.idle:
      case ComicReaderChapterPreloadStatus.imagesReady:
        return Icons.skip_next;
    }
  }

  String _nextEpisodeTooltip(ComicReaderViewState viewState) {
    if (!viewState.hasNextEpisode) {
      return '已是最后一话';
    }
    switch (viewState.nextChapterPreload.status) {
      case ComicReaderChapterPreloadStatus.loadingImages:
      case ComicReaderChapterPreloadStatus.preloadingPages:
        return '下一话预加载中';
      case ComicReaderChapterPreloadStatus.ready:
        return '下一话已预加载';
      case ComicReaderChapterPreloadStatus.failed:
        return '下一话预加载失败，点击加载';
      case ComicReaderChapterPreloadStatus.unavailable:
      case ComicReaderChapterPreloadStatus.idle:
      case ComicReaderChapterPreloadStatus.imagesReady:
        return '下一话';
    }
  }

  void _onVerticalScroll() {
    if (!_scrollController.hasClients || _isSliderCommitInFlight) {
      return;
    }
    _hideReaderMenuForContentMotion();
    _pulsePageIndicator();
    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }
    final ratio = (position.pixels / position.maxScrollExtent)
        .clamp(0.0, 1.0)
        .toDouble();
    final state = ref.read(comicReaderControllerProvider(_readerArgs));
    final total = state.value?.images.length ?? 0;
    if (total == 0) {
      return;
    }
    final preferences =
        ref.read(readerPreferencesControllerProvider).value ??
        ReaderPreferences.defaults();
    final items = _continuousImageAdapter.mapImages(
      episodeId: state.value!.episodeId,
      images: state.value!.images,
      pageSpacing: preferences.pageSpacing,
    );
    final index =
        _resolveVerticalActiveIndex(
          items,
          position.pixels,
          position.viewportDimension,
        ) ??
        ((total - 1) * ratio).round();
    if (index != _lastKnownIndex) {
      _lastKnownIndex = index;
      _controller().onScrollProgress(
        currentIndex: index,
        scrollOffset: position.pixels,
      );
    }
  }

  Future<void> _onPageChanged(int pageIndex) async {
    if (pageIndex == _lastKnownIndex) {
      return;
    }
    _hideReaderMenuForContentMotion();
    _pulsePageIndicator();
    _lastKnownIndex = pageIndex;
    _reportedVisibleImageIndexes.add(pageIndex);
    await _controller().jumpToImageIndex(pageIndex, scrollOffset: 0);
    _tryReleaseSliderCommitLock(pageIndex);
  }

  void _turnPageByTap({
    required ReaderModePreference mode,
    required ComicReaderViewState viewState,
    required bool isLeftTap,
  }) {
    if (_isAnyImageZoomed) {
      return;
    }
    final pageController = _pageController;
    if (pageController == null || !pageController.hasClients) {
      return;
    }

    final current = pageController.page?.round() ?? viewState.currentImageIndex;
    final isRtl = mode == ReaderModePreference.rtl;

    final isPreviousAction = isRtl ? !isLeftTap : isLeftTap;
    final delta = isPreviousAction ? -1 : 1;
    final target = (current + delta)
        .clamp(0, viewState.images.length - 1)
        .toInt();

    if (target == current) {
      return;
    }
    pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _onProgressChangeStart(double sliderValue, int maxLength) {
    final index = sliderValue.round().clamp(0, maxLength - 1).toInt();
    setState(() {
      _sliderPreviewIndex = index;
    });
  }

  void _onProgressChanged(double sliderValue, int maxLength) {
    final index = sliderValue.round().clamp(0, maxLength - 1).toInt();
    setState(() {
      _sliderPreviewIndex = index;
    });
  }

  Future<void> _onProgressChangeEnd({
    required double sliderValue,
    required ReaderModePreference mode,
    required ComicReaderViewState viewState,
    required ReaderPreferences preferences,
  }) async {
    final now = DateTime.now();
    if (_lastSliderCommitAt != null &&
        now.difference(_lastSliderCommitAt!) <
            const Duration(milliseconds: 120)) {
      return;
    }
    _lastSliderCommitAt = now;

    final targetIndex = sliderValue
        .round()
        .clamp(0, viewState.images.length - 1)
        .toInt();
    _pulsePageIndicator();

    setState(() {
      _isSliderCommitInFlight = true;
      _pendingCommittedIndex = targetIndex;
      _sliderPreviewIndex = targetIndex;
      _lastKnownIndex = targetIndex;
    });

    if (mode == ReaderModePreference.vertical) {
      final continuousItems = _continuousImageAdapter.mapImages(
        episodeId: viewState.episodeId,
        images: viewState.images,
        pageSpacing: preferences.pageSpacing,
      );
      await _jumpVerticalToIndex(targetIndex, continuousItems);
      await _controller().jumpToImageIndex(
        targetIndex,
        scrollOffset: _scrollController.hasClients
            ? _scrollController.offset
            : 0,
      );
      _tryReleaseSliderCommitLock(targetIndex);
      return;
    }

    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.jumpToPage(targetIndex);
    }
    await _controller().jumpToImageIndex(targetIndex, scrollOffset: 0);
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

  int? _resolveVerticalActiveIndex(
    List<ContinuousImageItem> items,
    double scrollOffset,
    double viewportExtent,
  ) {
    if (items.isEmpty || viewportExtent <= 0) {
      return null;
    }
    final endOffset = scrollOffset + viewportExtent;
    var cursor = 0.0;
    for (final item in items) {
      final extent = _imageExtentRegistry.extentOf(item.id);
      if (extent == null) {
        return null;
      }
      cursor += extent.mainAxisExtent;
      if (cursor >= endOffset) {
        return item.index;
      }
      cursor += item.spacingAfter;
    }
    return items.last.index;
  }

  Future<void> _jumpVerticalToIndex(
    int targetIndex,
    List<ContinuousImageItem> items,
  ) async {
    final totalImages = items.length;
    if (!_scrollController.hasClients || totalImages <= 1) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }
    final crossAxisExtent = MediaQuery.sizeOf(context).width;
    final estimatedOffset = _imageExtentRegistry.estimateOffsetForIndex(
      targetIndex,
      items,
      crossAxisExtent: crossAxisExtent,
      resolver: _continuousImageLayoutResolver,
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
    // Wait for next frame without creating an extra timer in tests.
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollController.hasClients) {
      return;
    }
    final latestMax = _scrollController.position.maxScrollExtent;
    final latestEstimatedOffset = _imageExtentRegistry.estimateOffsetForIndex(
      targetIndex,
      items,
      crossAxisExtent: crossAxisExtent,
      resolver: _continuousImageLayoutResolver,
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

  Widget _buildReaderContentLayer({
    required ComicReaderViewState viewState,
    required ReaderModePreference mode,
    required ReaderPreferences preferences,
    required ImageRequestHeaderBuilder imageHeaderBuilder,
  }) {
    final background = _readerBackgroundColor(preferences);
    final chromePalette = const ReaderChromePaletteResolver().resolve(
      Theme.of(context),
    );
    return Column(
      children: [
        if (viewState.hint != null)
          Container(
            width: double.infinity,
            color: chromePalette.chromeBackground,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              viewState.hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: chromePalette.onChromeVariant,
              ),
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: background,
            child: mode == ReaderModePreference.vertical
                ? _buildVerticalReaderView(
                    viewState,
                    preferences: preferences,
                    imageHeaderBuilder: imageHeaderBuilder,
                  )
                : _buildPagedReaderView(
                    viewState,
                    mode,
                    preferences: preferences,
                    imageHeaderBuilder: imageHeaderBuilder,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalReaderView(
    ComicReaderViewState viewState, {
    required ReaderPreferences preferences,
    required ImageRequestHeaderBuilder imageHeaderBuilder,
  }) {
    final continuousItems = _continuousImageAdapter.mapImages(
      episodeId: viewState.episodeId,
      images: viewState.images,
      pageSpacing: preferences.pageSpacing,
    );
    return ListView.builder(
      key: const Key('comic-reader-image-list'),
      controller: _scrollController,
      cacheExtent:
          MediaQuery.sizeOf(context).height *
          ContinuousImageFlowPolicy
              .comicVerticalReading
              .viewportCacheExtentFactor,
      padding: EdgeInsets.zero,
      itemCount: viewState.images.length + 1,
      itemBuilder: (context, index) {
        if (index == viewState.images.length) {
          return _ReaderNextChapterTransition(
            preload: viewState.nextChapterPreload,
            hasNextEpisode: viewState.hasNextEpisode,
            isSwitchingEpisode: viewState.isSwitchingEpisode,
            onOpenNext: () => _openAdjacentEpisode(viewState, previous: false),
          );
        }
        final image = viewState.images[index];
        return _buildReaderImage(
          viewState: viewState,
          image: image,
          continuousImageItem: continuousItems[index],
          index: index,
          preferences: preferences,
          imageHeaderBuilder: imageHeaderBuilder,
        );
      },
    );
  }

  Widget _buildPagedReaderView(
    ComicReaderViewState viewState,
    ReaderModePreference mode, {
    required ReaderPreferences preferences,
    required ImageRequestHeaderBuilder imageHeaderBuilder,
  }) {
    return PageView.builder(
      key: const Key('comic-reader-page-view'),
      controller: _pageController,
      physics: _isAnyImageZoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      reverse: mode == ReaderModePreference.rtl,
      onPageChanged: _onPageChanged,
      itemCount: viewState.images.length,
      itemBuilder: (context, index) {
        final image = viewState.images[index];
        return _buildReaderImage(
          viewState: viewState,
          image: image,
          continuousImageItem: null,
          index: index,
          preferences: preferences,
          imageHeaderBuilder: imageHeaderBuilder,
          paged: true,
        );
      },
    );
  }

  Widget _buildReaderImage({
    required ComicReaderViewState viewState,
    required ComicReaderImageState image,
    required ContinuousImageItem? continuousImageItem,
    required int index,
    required ReaderPreferences preferences,
    required ImageRequestHeaderBuilder imageHeaderBuilder,
    bool paged = false,
  }) {
    final imageUrl = image.imageUrl;
    final fit = _imageFitFor(preferences.pageFit, paged: paged);
    final imageWidget = ReaderZoomableImage(
      onZoomStateChanged: (isZoomed) =>
          _onImageZoomStateChanged(index, isZoomed),
      child: LibraryCachedImage(
        localPath: image.effectiveLocalPath,
        imageUrl: imageUrl,
        fit: fit,
        width: paged ? null : double.infinity,
        placeholder: _ReaderImageLoadingPlaceholder(
          paged: paged,
          imageIndex: index,
        ),
        errorPlaceholder: _ReaderImageErrorPlaceholder(
          imageUrl: imageUrl,
          paged: paged,
          onRetry: () => _controller().retryImage(imageUrl),
        ),
        headerBuilder: imageHeaderBuilder,
        onImageResolved: (size) => _controller().onImageResolved(
          imageIndex: index,
          imageUrl: imageUrl,
          width: size.width.round(),
          height: size.height.round(),
        ),
        onImageFailed: () => _controller().onImageDisplayFailed(
          imageIndex: index,
          imageUrl: imageUrl,
        ),
      ),
    );

    if (paged) {
      return Padding(
        padding: EdgeInsets.all(
          preferences.pageSpacing.clamp(0.0, 48.0).toDouble(),
        ),
        child: SizedBox.expand(child: imageWidget),
      );
    }

    return Column(
      children: [
        _ReaderImageSlot(
          imageIndex: index,
          imageItem:
              continuousImageItem ??
              _continuousImageAdapter.mapImage(
                episodeId: viewState.episodeId,
                image: image,
                pageSpacing: preferences.pageSpacing,
              ),
          layoutResolver: _continuousImageLayoutResolver,
          onExtentResolved: _recordContinuousImageExtent,
          child: imageWidget,
        ),
        SizedBox(height: preferences.pageSpacing.clamp(0.0, 48.0).toDouble()),
      ],
    );
  }

  bool get _isAnyImageZoomed =>
      _zoomedStateByIndex.values.any((isZoomed) => isZoomed);

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

  Color _readerBackgroundColor(ReaderPreferences preferences) {
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

  Future<void> _handleReaderMoreAction(
    _ComicReaderMoreAction action,
    ComicReaderViewState viewState,
  ) async {
    switch (action) {
      case _ComicReaderMoreAction.markReadToggle:
        await _controller().setCurrentEpisodeRead(
          !viewState.isCurrentEpisodeRead,
        );
        break;
      case _ComicReaderMoreAction.setCurrentPageAsCover:
        await _controller().setCurrentImageAsCover();
        break;
      case _ComicReaderMoreAction.cacheEpisode:
        await _controller().cacheCurrentEpisode();
        break;
      case _ComicReaderMoreAction.cacheUnread:
        await _controller().cacheAllUnread();
        break;
      case _ComicReaderMoreAction.clearEpisodeCache:
        await _controller().clearCurrentEpisodeCache();
        break;
      case _ComicReaderMoreAction.retryFailedImages:
        await _controller().retryFailedImages();
        break;
    }
  }

  Future<void> _showMoreActionSheet(ComicReaderViewState viewState) async {
    _overlayController.hideMenu();
    final action = await showModalBottomSheet<_ComicReaderMoreAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => ReaderActionSheet<_ComicReaderMoreAction>(
        title: '更多操作',
        items: [
          ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'mark-read-toggle',
            value: _ComicReaderMoreAction.markReadToggle,
            icon: viewState.isCurrentEpisodeRead
                ? Icons.radio_button_unchecked
                : Icons.check_circle_outline,
            label: viewState.isCurrentEpisodeRead ? '标记本章未读' : '标记本章已读',
          ),
          const ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'set-cover',
            value: _ComicReaderMoreAction.setCurrentPageAsCover,
            icon: Icons.image_outlined,
            label: '将当前页设为封面',
          ),
          const ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'cache-episode',
            value: _ComicReaderMoreAction.cacheEpisode,
            icon: Icons.download_for_offline_outlined,
            label: '缓存本章',
          ),
          const ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'cache-unread',
            value: _ComicReaderMoreAction.cacheUnread,
            icon: Icons.download_done_outlined,
            label: '缓存未读章节',
          ),
          const ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'clear-cache',
            value: _ComicReaderMoreAction.clearEpisodeCache,
            icon: Icons.cleaning_services_outlined,
            label: '清除本章缓存',
          ),
          ReaderActionSheetItem<_ComicReaderMoreAction>(
            id: 'retry-failed',
            value: _ComicReaderMoreAction.retryFailedImages,
            icon: Icons.refresh,
            label: viewState.failedImageCount > 0
                ? '重试失败图片（${viewState.failedImageCount}）'
                : '重试失败图片',
            enabled: viewState.failedImageCount > 0,
          ),
        ],
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    await _handleReaderMoreAction(action, viewState);
  }

  Future<void> _openSourceThread(ComicReaderViewState viewState) async {
    _overlayController.hideMenu();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: viewState.sourceTid,
          subject: viewState.episodeTitle,
        ),
      ),
    );
  }

  Future<void> _openAdjacentEpisode(
    ComicReaderViewState viewState, {
    required bool previous,
  }) async {
    if (viewState.isSwitchingEpisode) {
      return;
    }
    final targetEpisodeId = previous
        ? await _controller().goToPreviousEpisode()
        : await _controller().goToNextEpisode();
    if (targetEpisodeId == null || !mounted) {
      return;
    }
    if (!previous) {
      await _controller().ensureNextChapterPreloaded();
      if (!mounted) {
        return;
      }
    }
    final switched = await _controller().goToEpisode(targetEpisodeId);
    if (!switched || !mounted) {
      return;
    }
    _resetReaderPositionForEpisodeSwitch();
    _hideReaderMenuForContentMotion();
  }

  void _resetReaderPositionForEpisodeSwitch() {
    _reportedVisibleImageIndexes.clear();
    _zoomedStateByIndex.clear();
    _lastKnownIndex = 0;
    _sliderPreviewIndex = null;
    _pendingCommittedIndex = null;
    _isSliderCommitInFlight = false;
    _lastPagedRestoreKey = null;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.jumpToPage(0);
    }
  }

  Future<void> _showModeSheet(ComicReaderViewState viewState) async {
    _overlayController.hideMenu();
    final currentMode =
        ref.read(readerPreferencesControllerProvider).value?.readerMode ??
        ReaderModePreference.vertical;
    final selected = await showModalBottomSheet<ReaderModePreference>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<ReaderModePreference>(
          groupValue: currentMode,
          onChanged: (value) {
            if (value != null) {
              Navigator.of(context).pop(value);
            }
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReaderSheetTitle(title: '阅读模式'),
              _ReaderModeTile(
                mode: ReaderModePreference.vertical,
                icon: Icons.view_stream_outlined,
                label: '垂直连续',
              ),
              _ReaderModeTile(
                mode: ReaderModePreference.ltr,
                icon: Icons.swipe_left_outlined,
                label: '单页 左到右',
              ),
              _ReaderModeTile(
                mode: ReaderModePreference.rtl,
                icon: Icons.swipe_right_outlined,
                label: '单页 右到左',
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    await _onReaderModeChanged(selected, viewState);
  }

  Future<void> _showChapterListSheet(ComicReaderViewState viewState) async {
    _overlayController.hideMenu();
    final selected = await showModalBottomSheet<ComicReaderChapterEntry>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            _ReaderSheetTitle(title: '章节列表'),
            for (final chapter in viewState.chapters)
              ListTile(
                key: ValueKey<String>(
                  'comic-reader-chapter-${chapter.episodeId}',
                ),
                selected: chapter.isCurrent,
                leading: Icon(
                  chapter.isRead
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chapter.isCurrent ? const Text('当前') : null,
                onTap: () => Navigator.of(context).pop(chapter),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected.isCurrent || !mounted) {
      return;
    }
    if (selected.episodeId == viewState.nextChapterPreload.episodeId) {
      await _controller().ensureNextChapterPreloaded();
      if (!mounted) {
        return;
      }
    }
    final switched = await _controller().goToEpisode(selected.episodeId);
    if (!switched || !mounted) {
      return;
    }
    _resetReaderPositionForEpisodeSwitch();
  }

  void _showDisplaySettingsSheet(
    ReaderPreferences preferences,
    ComicReaderViewState viewState,
  ) {
    _overlayController.hideMenu();
    final preferencesController = ref.read(
      readerPreferencesControllerProvider.notifier,
    );
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => _ReaderDisplaySettingsSheet(
          preferences: preferences,
          onModeChanged: (mode) =>
              unawaited(_onReaderModeChanged(mode, viewState)),
          onPageFitChanged: (value) =>
              unawaited(preferencesController.setPageFit(value)),
          onBackgroundChanged: (value) =>
              unawaited(preferencesController.setBackground(value)),
          onPageSpacingChanged: (value) =>
              unawaited(preferencesController.setPageSpacing(value)),
          onShowPageIndicatorChanged: (value) =>
              unawaited(preferencesController.setShowPageIndicator(value)),
        ),
      ),
    );
  }

  void _hideReaderMenuForContentMotion() {
    if (!_overlayController.isMenuVisible || _isSliderCommitInFlight) {
      return;
    }
    _overlayController.hideMenu();
  }

  void _onOverlayVisibilityChanged() {
    if (mounted) {
      setState(() {});
    }
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

class _ReaderImageSlot extends StatelessWidget {
  const _ReaderImageSlot({
    required this.imageIndex,
    required this.imageItem,
    required this.layoutResolver,
    required this.onExtentResolved,
    required this.child,
  });

  final int imageIndex;
  final ContinuousImageItem imageItem;
  final ContinuousImageLayoutResolver layoutResolver;
  final ValueChanged<ContinuousImageExtent> onExtentResolved;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: ValueKey<String>('comic-reader-image-slot-$imageIndex'),
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final expectedHeight = _expectedHeight(width);
        final aspectRatio = width > 0
            ? width / expectedHeight
            : imageItem.fallbackAspectRatio;
        return ContinuousImageExtentObserver(
          item: imageItem,
          aspectRatio: aspectRatio,
          dimensionSource: imageItem.knownDimensions == null
              ? ContinuousImageDimensionSource.fallback
              : imageItem.effectiveKnownDimensionSource,
          onExtentResolved: onExtentResolved,
          child: ConstrainedBox(
            // Prefer decoded image dimensions once known. This makes reopening
            // long chapters steadier while still letting first-open pages grow
            // naturally after the image is resolved.
            constraints: BoxConstraints(minHeight: expectedHeight),
            child: ClipRect(child: child),
          ),
        );
      },
    );
  }

  double _expectedHeight(double width) {
    final hint = layoutResolver.resolveInitialHint(item: imageItem);
    return width / hint.aspectRatio;
  }
}

class _ReaderNextChapterTransition extends StatelessWidget {
  const _ReaderNextChapterTransition({
    required this.preload,
    required this.hasNextEpisode,
    required this.isSwitchingEpisode,
    required this.onOpenNext,
  });

  final ComicReaderChapterPreloadState preload;
  final bool hasNextEpisode;
  final bool isSwitchingEpisode;
  final VoidCallback onOpenNext;

  @override
  Widget build(BuildContext context) {
    if (!hasNextEpisode) {
      return const SizedBox.shrink(
        key: Key('comic-reader-next-chapter-transition-empty'),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chromePalette = const ReaderChromePaletteResolver().resolve(theme);
    final canOpen = preload.canOpen && !isSwitchingEpisode;
    return Padding(
      key: const Key('comic-reader-next-chapter-transition'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 56),
      child: Material(
        color: chromePalette.transitionCardBackground,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const Key('comic-reader-next-chapter-transition-button'),
          borderRadius: BorderRadius.circular(8),
          onTap: canOpen ? onOpenNext : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(_iconFor(preload.status), color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasNextEpisode
                            ? '下一章：${preload.displayTitle}'
                            : '已是最后一章',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isSwitchingEpisode)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: canOpen ? scheme.primary : scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(ComicReaderChapterPreloadStatus status) {
    switch (status) {
      case ComicReaderChapterPreloadStatus.loadingImages:
      case ComicReaderChapterPreloadStatus.preloadingPages:
        return Icons.downloading_outlined;
      case ComicReaderChapterPreloadStatus.ready:
        return Icons.offline_bolt_outlined;
      case ComicReaderChapterPreloadStatus.failed:
        return Icons.error_outline;
      case ComicReaderChapterPreloadStatus.unavailable:
        return Icons.done_all;
      case ComicReaderChapterPreloadStatus.idle:
      case ComicReaderChapterPreloadStatus.imagesReady:
        return Icons.skip_next;
    }
  }

  String _subtitle() {
    if (!hasNextEpisode) {
      return preload.message ?? '没有更多章节';
    }
    if (isSwitchingEpisode) {
      return '正在切换章节';
    }
    switch (preload.status) {
      case ComicReaderChapterPreloadStatus.loadingImages:
        return '正在获取图片列表';
      case ComicReaderChapterPreloadStatus.imagesReady:
        return '图片列表已就绪';
      case ComicReaderChapterPreloadStatus.preloadingPages:
        return '正在缓存下一章前几页';
      case ComicReaderChapterPreloadStatus.ready:
        return preload.cachedPageCount > 0
            ? '已预加载 ${preload.cachedPageCount} 页'
            : '已准备好';
      case ComicReaderChapterPreloadStatus.failed:
        return preload.message ?? '预加载失败，点击后重新加载';
      case ComicReaderChapterPreloadStatus.unavailable:
        return preload.message ?? '没有更多章节';
      case ComicReaderChapterPreloadStatus.idle:
        return '点击进入下一章';
    }
  }
}

class _ReaderSheetTitle extends StatelessWidget {
  const _ReaderSheetTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _ReaderModeTile extends StatelessWidget {
  const _ReaderModeTile({
    required this.mode,
    required this.icon,
    required this.label,
  });

  final ReaderModePreference mode;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('comic-reader-mode-${mode.name}'),
      leading: Icon(icon),
      title: Text(label),
      trailing: Radio<ReaderModePreference>(value: mode),
      onTap: () => Navigator.of(context).pop(mode),
    );
  }
}

class _ReaderDisplaySettingsSheet extends StatelessWidget {
  const _ReaderDisplaySettingsSheet({
    required this.preferences,
    required this.onModeChanged,
    required this.onPageFitChanged,
    required this.onBackgroundChanged,
    required this.onPageSpacingChanged,
    required this.onShowPageIndicatorChanged,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderModePreference> onModeChanged;
  final ValueChanged<ReaderPageFitPreference> onPageFitChanged;
  final ValueChanged<ReaderBackgroundPreference> onBackgroundChanged;
  final ValueChanged<double> onPageSpacingChanged;
  final ValueChanged<bool> onShowPageIndicatorChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _ReaderDisplaySettingsContent(
        preferences: preferences,
        onModeChanged: onModeChanged,
        onPageFitChanged: onPageFitChanged,
        onBackgroundChanged: onBackgroundChanged,
        onPageSpacingChanged: onPageSpacingChanged,
        onShowPageIndicatorChanged: onShowPageIndicatorChanged,
      ),
    );
  }
}

class _ReaderDisplaySettingsContent extends StatefulWidget {
  const _ReaderDisplaySettingsContent({
    required this.preferences,
    required this.onModeChanged,
    required this.onPageFitChanged,
    required this.onBackgroundChanged,
    required this.onPageSpacingChanged,
    required this.onShowPageIndicatorChanged,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderModePreference> onModeChanged;
  final ValueChanged<ReaderPageFitPreference> onPageFitChanged;
  final ValueChanged<ReaderBackgroundPreference> onBackgroundChanged;
  final ValueChanged<double> onPageSpacingChanged;
  final ValueChanged<bool> onShowPageIndicatorChanged;

  @override
  State<_ReaderDisplaySettingsContent> createState() =>
      _ReaderDisplaySettingsContentState();
}

class _ReaderDisplaySettingsContentState
    extends State<_ReaderDisplaySettingsContent> {
  late ReaderPreferences _current;

  @override
  void initState() {
    super.initState();
    _current = widget.preferences;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('comic-reader-display-settings-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const _ReaderSheetTitle(title: '显示设置'),
        SizedBox(
          key: ValueKey<String>(
            'comic-reader-settings-mode-${_current.readerMode.name}',
          ),
          height: 0,
        ),
        _EnumSegment<ReaderModePreference>(
          label: '阅读模式',
          value: _current.readerMode,
          values: ReaderModePreference.values,
          labelBuilder: _readerModeLabel,
          onChanged: (value) {
            setState(() => _current = _current.copyWith(readerMode: value));
            widget.onModeChanged(value);
          },
        ),
        SizedBox(
          key: ValueKey<String>(
            'comic-reader-settings-fit-${_current.pageFit.name}',
          ),
          height: 0,
        ),
        _EnumSegment<ReaderPageFitPreference>(
          label: '页面适配',
          value: _current.pageFit,
          values: ReaderPageFitPreference.values,
          labelBuilder: _pageFitLabel,
          onChanged: (value) {
            setState(() => _current = _current.copyWith(pageFit: value));
            widget.onPageFitChanged(value);
          },
        ),
        SizedBox(
          key: ValueKey<String>(
            'comic-reader-settings-background-${_current.background.name}',
          ),
          height: 0,
        ),
        _EnumSegment<ReaderBackgroundPreference>(
          label: '背景色',
          value: _current.background,
          values: ReaderBackgroundPreference.values,
          labelBuilder: _backgroundLabel,
          onChanged: (value) {
            setState(() => _current = _current.copyWith(background: value));
            widget.onBackgroundChanged(value);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              const SizedBox(width: 88, child: Text('页间距')),
              Expanded(
                child: Slider(
                  key: const Key('comic-reader-page-spacing-slider'),
                  value: _current.pageSpacing.clamp(0.0, 48.0).toDouble(),
                  min: 0,
                  max: 48,
                  divisions: 12,
                  label: _current.pageSpacing.round().toString(),
                  onChanged: (value) {
                    setState(
                      () => _current = _current.copyWith(pageSpacing: value),
                    );
                    widget.onPageSpacingChanged(value);
                  },
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('comic-reader-page-indicator-switch'),
          title: const Text('页码浮层'),
          value: _current.showPageIndicator,
          onChanged: (value) {
            setState(
              () => _current = _current.copyWith(showPageIndicator: value),
            );
            widget.onShowPageIndicatorChanged(value);
          },
        ),
      ],
    );
  }

  String _readerModeLabel(ReaderModePreference value) {
    switch (value) {
      case ReaderModePreference.vertical:
        return '垂直';
      case ReaderModePreference.ltr:
        return 'LTR';
      case ReaderModePreference.rtl:
        return 'RTL';
    }
  }

  String _pageFitLabel(ReaderPageFitPreference value) {
    switch (value) {
      case ReaderPageFitPreference.fitWidth:
        return '宽度';
      case ReaderPageFitPreference.fitHeight:
        return '高度';
      case ReaderPageFitPreference.contain:
        return '屏幕';
      case ReaderPageFitPreference.original:
        return '原始';
    }
  }

  String _backgroundLabel(ReaderBackgroundPreference value) {
    switch (value) {
      case ReaderBackgroundPreference.followTheme:
        return '主题';
      case ReaderBackgroundPreference.black:
        return '黑';
      case ReaderBackgroundPreference.white:
        return '白';
      case ReaderBackgroundPreference.gray:
        return '灰';
    }
  }
}

class _EnumSegment<T extends Object> extends StatelessWidget {
  const _EnumSegment({
    required this.label,
    required this.value,
    required this.values,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: SegmentedButton<T>(
              segments: [
                for (final item in values)
                  ButtonSegment<T>(
                    value: item,
                    label: Text(labelBuilder(item)),
                  ),
              ],
              selected: {value},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  onChanged(selection.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderImageLoadingPlaceholder extends StatelessWidget {
  const _ReaderImageLoadingPlaceholder({
    required this.paged,
    required this.imageIndex,
  });

  final bool paged;
  final int imageIndex;

  @override
  Widget build(BuildContext context) {
    final content = _ReaderLoadingIndicator(
      key: ValueKey<String>('comic-reader-image-loading-$imageIndex'),
      text: '图片加载中',
    );

    if (paged) {
      return Center(child: content);
    }
    final chromePalette = const ReaderChromePaletteResolver().resolve(
      Theme.of(context),
    );
    return ColoredBox(
      color: chromePalette.imageLoadingPlaceholderBackground,
      child: Center(child: content),
    );
  }
}

class _ReaderOpeningPlaceholder extends StatefulWidget {
  const _ReaderOpeningPlaceholder({required this.background});

  final Color background;

  @override
  State<_ReaderOpeningPlaceholder> createState() =>
      _ReaderOpeningPlaceholderState();
}

class _ReaderOpeningPlaceholderState extends State<_ReaderOpeningPlaceholder> {
  static const Duration _revealDelay = Duration(milliseconds: 160);

  Timer? _timer;
  bool _showCopy = false;

  @override
  void initState() {
    super.initState();
    // Most chapter metadata loads within a frame or two.  Holding the visible
    // opening copy briefly prevents a transient page-level placeholder from
    // flashing before the real image placeholder takes over.
    _timer = Timer(_revealDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showCopy = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('comic-reader-page-opening'),
      color: widget.background,
      child: Center(
        child: _showCopy
            ? Text('正在打开章节', style: Theme.of(context).textTheme.bodySmall)
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _ReaderLoadingIndicator extends StatelessWidget {
  const _ReaderLoadingIndicator({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: 10),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ReaderImageErrorPlaceholder extends StatelessWidget {
  const _ReaderImageErrorPlaceholder({
    required this.imageUrl,
    required this.paged,
    required this.onRetry,
  });

  final String imageUrl;
  final bool paged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: paged ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('图片加载失败'),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ValueKey<String>('comic-reader-retry-$imageUrl'),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ],
    );

    if (paged) {
      return Center(child: content);
    }
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: content,
      ),
    );
  }
}
