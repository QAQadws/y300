import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/providers/reader_preferences_provider.dart';
import 'package:y300/features/comic/presentation/widgets/reader_bottom_panel.dart';
import 'package:y300/features/comic/presentation/widgets/reader_tap_zones.dart';
import 'package:y300/features/comic/presentation/widgets/reader_top_bar.dart';
import 'package:y300/features/comic/presentation/widgets/reader_zoomable_image.dart';

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

class _ComicReaderPageState extends ConsumerState<ComicReaderPage>
    with SingleTickerProviderStateMixin {
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

  bool _isMenuVisible = false;
  late final AnimationController _menuAnimationController;
  late final Animation<Offset> _topMenuSlideAnimation;
  late final Animation<Offset> _bottomMenuSlideAnimation;
  // Keep per-image zoom flags so page-level gestures can be coordinated
  // without coupling gesture logic into image rendering code.
  final Map<int, bool> _zoomedStateByIndex = <int, bool>{};

  ComicReaderArgs get _readerArgs =>
      ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onVerticalScroll);
    _menuAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _topMenuSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _menuAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _bottomMenuSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _menuAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onVerticalScroll)
      ..dispose();
    _pageController?.dispose();
    _menuAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferencesState = ref.watch(readerPreferencesControllerProvider);
    final mode = preferencesState.value?.readerMode ?? ReaderModePreference.vertical;

    final state = ref.watch(comicReaderControllerProvider(_readerArgs));
    final imageHeaderBuilder = ref.watch(imageRequestHeaderBuilderProvider);

    return Scaffold(
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('加载阅读器失败：$error')),
        data: (viewState) {
          if (viewState.images.isEmpty) {
            return const Center(child: Text('当前章节没有可阅读图片'));
          }

          _syncPageControllerIfNeeded(mode, viewState.currentImageIndex);
          _restorePositionIfNeeded(mode, viewState);

          return Stack(
            children: [
              _buildReaderContentLayer(
                viewState: viewState,
                mode: mode,
                imageHeaderBuilder: imageHeaderBuilder,
              ),
              ReaderTapZones(
                onCenterTap: _toggleReaderMenu,
                onLeftTap: mode == ReaderModePreference.vertical
                    ? null
                    : () => _turnPageByTap(mode: mode, viewState: viewState, isLeftTap: true),
                onRightTap: mode == ReaderModePreference.vertical
                    ? null
                    : () => _turnPageByTap(mode: mode, viewState: viewState, isLeftTap: false),
                enabled: !_isAnyImageZoomed,
              ),
              _buildReaderTopOverlayLayer(viewState),
              _buildReaderBottomOverlayLayer(viewState, mode),
            ],
          );
        },
      ),
    );
  }

  ComicReaderController _controller() {
    return ref.read(comicReaderControllerProvider(_readerArgs).notifier);
  }

  Future<void> _onReaderModeChanged(
    ReaderModePreference nextMode,
    ComicReaderViewState viewState,
  ) async {
    final currentMode = ref.read(readerPreferencesControllerProvider).value?.readerMode ??
        ReaderModePreference.vertical;
    if (currentMode == nextMode) {
      return;
    }

    final targetIndex = _resolveCurrentLogicalIndex(
      mode: currentMode,
      fallbackIndex: viewState.currentImageIndex,
      maxLength: viewState.images.length,
    );

    await ref.read(readerPreferencesControllerProvider.notifier).setReaderMode(nextMode);

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
      return fallbackIndex.clamp(0, maxIndex);
    }
    final currentPage = _pageController?.hasClients == true
        ? _pageController!.page?.round()
        : _pageController?.initialPage;
    return (currentPage ?? fallbackIndex).clamp(0, maxIndex);
  }

  void _syncPageControllerIfNeeded(
    ReaderModePreference mode,
    int initialIndex,
  ) {
    if (mode == ReaderModePreference.vertical) {
      return;
    }
    final expectedInitialPage = initialIndex.clamp(0, 1 << 20);
    final controller = _pageController;
    if (controller == null) {
      _pageController = PageController(initialPage: expectedInitialPage);
      return;
    }
    if (!controller.hasClients && controller.initialPage != expectedInitialPage) {
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
      final pageController = _pageController;
      if (pageController == null || !pageController.hasClients) {
        return;
      }
      final targetPage = viewState.currentImageIndex;
      final currentPage = pageController.page?.round() ?? pageController.initialPage;
      if (currentPage != targetPage) {
        pageController.jumpToPage(targetPage);
      }
    });
  }

  void _onVerticalScroll() {
    if (!_scrollController.hasClients || _isSliderCommitInFlight) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }
    final ratio = (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
    final state = ref.read(comicReaderControllerProvider(_readerArgs));
    final total = state.value?.images.length ?? 0;
    if (total == 0) {
      return;
    }
    final index = ((total - 1) * ratio).round();
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
    _lastKnownIndex = pageIndex;
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
    final target = (current + delta).clamp(0, viewState.images.length - 1);

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
    final index = sliderValue.round().clamp(0, maxLength - 1);
    setState(() {
      _sliderPreviewIndex = index;
    });
  }

  void _onProgressChanged(double sliderValue, int maxLength) {
    final index = sliderValue.round().clamp(0, maxLength - 1);
    setState(() {
      _sliderPreviewIndex = index;
    });
  }

  Future<void> _onProgressChangeEnd({
    required double sliderValue,
    required ReaderModePreference mode,
    required ComicReaderViewState viewState,
  }) async {
    final now = DateTime.now();
    if (_lastSliderCommitAt != null &&
        now.difference(_lastSliderCommitAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastSliderCommitAt = now;

    final targetIndex = sliderValue.round().clamp(0, viewState.images.length - 1);

    setState(() {
      _isSliderCommitInFlight = true;
      _pendingCommittedIndex = targetIndex;
      _sliderPreviewIndex = targetIndex;
      _lastKnownIndex = targetIndex;
    });

    if (mode == ReaderModePreference.vertical) {
      await _jumpVerticalToIndex(targetIndex, viewState.images.length);
      await _controller().jumpToImageIndex(
        targetIndex,
        scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
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
    if (!_isSliderCommitInFlight || _pendingCommittedIndex != reachedIndex || !mounted) {
      return;
    }
    setState(() {
      _isSliderCommitInFlight = false;
      _pendingCommittedIndex = null;
      _sliderPreviewIndex = null;
    });
  }

  Future<void> _jumpVerticalToIndex(int targetIndex, int totalImages) async {
    if (!_scrollController.hasClients || totalImages <= 1) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }
    final ratio = targetIndex / (totalImages - 1);
    final offset = (maxScroll * ratio).clamp(0.0, maxScroll);
    _scrollController.jumpTo(offset);
    // Wait for next frame without creating an extra timer in tests.
    await WidgetsBinding.instance.endOfFrame;
    if (!_scrollController.hasClients) {
      return;
    }
    final latestMax = _scrollController.position.maxScrollExtent;
    final correctedOffset = (latestMax * ratio).clamp(0.0, latestMax);
    if ((_scrollController.offset - correctedOffset).abs() > 1.5) {
      _scrollController.jumpTo(correctedOffset);
    }
  }

  Widget _buildReaderContentLayer({
    required ComicReaderViewState viewState,
    required ReaderModePreference mode,
    required ImageRequestHeaderBuilder imageHeaderBuilder,
  }) {
    return Column(
      children: [
        if (viewState.hint != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              viewState.hint!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: mode == ReaderModePreference.vertical
              ? _buildVerticalReaderView(
                  viewState,
                  imageHeaderBuilder: imageHeaderBuilder,
                )
              : _buildPagedReaderView(
                  viewState,
                  mode,
                  imageHeaderBuilder: imageHeaderBuilder,
                ),
        ),
      ],
    );
  }

  Widget _buildVerticalReaderView(
    ComicReaderViewState viewState, {
    required ImageRequestHeaderBuilder imageHeaderBuilder,
  }) {
    return ListView.builder(
      key: const Key('comic-reader-image-list'),
      controller: _scrollController,
      itemCount: viewState.images.length,
      itemBuilder: (context, index) {
        final image = viewState.images[index];
        return _buildReaderImage(
          viewState: viewState,
          image: image,
          index: index,
          imageHeaderBuilder: imageHeaderBuilder,
        );
      },
    );
  }

  Widget _buildPagedReaderView(
    ComicReaderViewState viewState,
    ReaderModePreference mode, {
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
          index: index,
          imageHeaderBuilder: imageHeaderBuilder,
          paged: true,
        );
      },
    );
  }

  Widget _buildReaderImage({
    required ComicReaderViewState viewState,
    required ComicReaderImageState image,
    required int index,
    required ImageRequestHeaderBuilder imageHeaderBuilder,
    bool paged = false,
  }) {
    final imageUrl = image.imageUrl;
    final imageWidget = ReaderZoomableImage(
      onZoomStateChanged: (isZoomed) => _onImageZoomStateChanged(index, isZoomed),
      child: LibraryCachedImage(
        localPath: image.effectiveLocalPath,
        imageUrl: imageUrl,
        fit: paged ? BoxFit.contain : BoxFit.fitWidth,
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
      ),
    );

    if (paged) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: SizedBox.expand(child: imageWidget),
      );
    }

    return Column(
      children: [
        _ReaderImageSlot(
          imageIndex: index,
          child: imageWidget,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  bool get _isAnyImageZoomed => _zoomedStateByIndex.values.any((isZoomed) => isZoomed);

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

  Widget _buildReaderTopOverlayLayer(ComicReaderViewState viewState) {
    return Positioned(
      key: const Key('comic-reader-top-overlay'),
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_isMenuVisible,
        child: SlideTransition(
          position: _topMenuSlideAnimation,
          child: ReaderTopBar(
            episodeTitle: viewState.episodeTitle,
            onBack: () => Navigator.of(context).pop(),
            onCacheEpisode: () => _controller().cacheCurrentEpisode(),
            onCacheUnread: () => _controller().cacheAllUnread(),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderBottomOverlayLayer(
    ComicReaderViewState viewState,
    ReaderModePreference mode,
  ) {
    final currentIndex = _sliderPreviewIndex ?? viewState.currentImageIndex;
    final total = viewState.images.length;

    return Positioned(
      key: const Key('comic-reader-bottom-overlay'),
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_isMenuVisible,
        child: SlideTransition(
          position: _bottomMenuSlideAnimation,
          child: ReaderBottomPanel(
            currentMode: mode,
            onModeChanged: (nextMode) => _onReaderModeChanged(nextMode, viewState),
            currentPage: currentIndex + 1,
            totalPages: total,
            hasPreviousEpisode: viewState.hasPreviousEpisode,
            hasNextEpisode: viewState.hasNextEpisode,
            onPreviousEpisode: () => Navigator.of(context).pop('previous'),
            onNextEpisode: () => Navigator.of(context).pop('next'),
            onProgressChangeStart: (value) => _onProgressChangeStart(value, total),
            onProgressChanged: (value) => _onProgressChanged(value, total),
            onProgressChangeEnd: (value) => _onProgressChangeEnd(
              sliderValue: value,
              mode: mode,
              viewState: viewState,
            ),
            isProgressInteractionLocked: _isSliderCommitInFlight,
          ),
        ),
      ),
    );
  }

  void _toggleReaderMenu() {
    setState(() {
      _isMenuVisible = !_isMenuVisible;
    });
    if (_isMenuVisible) {
      _menuAnimationController.forward();
      return;
    }
    _menuAnimationController.reverse();
  }
}

class _ReaderImageSlot extends StatelessWidget {
  const _ReaderImageSlot({
    required this.imageIndex,
    required this.child,
  });

  final int imageIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: ValueKey<String>('comic-reader-image-slot-$imageIndex'),
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return ConstrainedBox(
          // Reserve a portrait comic-page footprint while still allowing the
          // loaded image to grow to its real fitWidth height.
          constraints: BoxConstraints(minHeight: width * 4 / 3),
          child: ClipRect(child: child),
        );
      },
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
    final content = Column(
      key: ValueKey<String>('comic-reader-image-loading-$imageIndex'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: 10),
        Text(
          '图片加载中',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    if (paged) {
      return Center(child: content);
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(96),
      child: Center(child: content),
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

