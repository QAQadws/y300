import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/providers/reader_preferences_provider.dart';
import 'package:y300/features/comic/presentation/widgets/reader_bottom_panel.dart';
import 'package:y300/features/comic/presentation/widgets/reader_tap_zones.dart';
import 'package:y300/features/comic/presentation/widgets/reader_top_bar.dart';

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

  // Preview index used while dragging slider thumb.
  int? _sliderPreviewIndex;

  bool _isMenuVisible = false;
  late final AnimationController _menuAnimationController;
  late final Animation<Offset> _topMenuSlideAnimation;
  late final Animation<Offset> _bottomMenuSlideAnimation;

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
              _buildReaderContentLayer(viewState: viewState, mode: mode),
              ReaderTapZones(
                onCenterTap: _toggleReaderMenu,
                onLeftTap: mode == ReaderModePreference.vertical
                    ? null
                    : () => _turnPageByTap(mode: mode, viewState: viewState, isLeftTap: true),
                onRightTap: mode == ReaderModePreference.vertical
                    ? null
                    : () => _turnPageByTap(mode: mode, viewState: viewState, isLeftTap: false),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
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
    if (!_scrollController.hasClients) {
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
  }

  void _turnPageByTap({
    required ReaderModePreference mode,
    required ComicReaderViewState viewState,
    required bool isLeftTap,
  }) {
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
    final targetIndex = sliderValue.round().clamp(0, viewState.images.length - 1);

    setState(() {
      _sliderPreviewIndex = null;
      _lastKnownIndex = targetIndex;
    });

    if (mode == ReaderModePreference.vertical) {
      _jumpVerticalToIndex(targetIndex, viewState.images.length);
      await _controller().jumpToImageIndex(targetIndex, scrollOffset: _scrollController.offset);
      return;
    }

    final pageController = _pageController;
    if (pageController != null && pageController.hasClients) {
      pageController.jumpToPage(targetIndex);
    }
    await _controller().jumpToImageIndex(targetIndex, scrollOffset: 0);
  }

  void _jumpVerticalToIndex(int targetIndex, int totalImages) {
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
  }

  Widget _buildReaderContentLayer({
    required ComicReaderViewState viewState,
    required ReaderModePreference mode,
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
              ? _buildVerticalReaderView(viewState)
              : _buildPagedReaderView(viewState, mode),
        ),
      ],
    );
  }

  Widget _buildVerticalReaderView(ComicReaderViewState viewState) {
    return ListView.builder(
      key: const Key('comic-reader-image-list'),
      controller: _scrollController,
      itemCount: viewState.images.length,
      itemBuilder: (context, index) {
        final image = viewState.images[index];
        return _buildReaderImage(viewState: viewState, imageUrl: image.imageUrl, index: index);
      },
    );
  }

  Widget _buildPagedReaderView(
    ComicReaderViewState viewState,
    ReaderModePreference mode,
  ) {
    return PageView.builder(
      key: const Key('comic-reader-page-view'),
      controller: _pageController,
      reverse: mode == ReaderModePreference.rtl,
      onPageChanged: _onPageChanged,
      itemCount: viewState.images.length,
      itemBuilder: (context, index) {
        final image = viewState.images[index];
        return _buildReaderImage(
          viewState: viewState,
          imageUrl: image.imageUrl,
          index: index,
          paged: true,
        );
      },
    );
  }

  Widget _buildReaderImage({
    required ComicReaderViewState viewState,
    required String imageUrl,
    required int index,
    bool paged = false,
  }) {
    if (paged) {
      // In paged mode each page has strict viewport constraints.
      // Use contain-fit image inside the page box to prevent RenderFlex overflow.
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, placeholderUrl) => Center(
              child: Text('加载中 ${index + 1}/${viewState.images.length}'),
            ),
            errorWidget: (context, errorUrl, error) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('图片加载失败'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: ValueKey<String>('comic-reader-retry-$imageUrl'),
                      onPressed: () => _controller().retryImage(imageUrl),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    return Column(
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          placeholder: (context, placeholderUrl) => AspectRatio(
            aspectRatio: 3 / 4,
            child: Center(
              child: Text('加载中 ${index + 1}/${viewState.images.length}'),
            ),
          ),
          errorWidget: (context, errorUrl, error) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Text('图片加载失败'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: ValueKey<String>('comic-reader-retry-$imageUrl'),
                    onPressed: () => _controller().retryImage(imageUrl),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
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
            onProgressChanged: (value) => _onProgressChanged(value, total),
            onProgressChangeEnd: (value) => _onProgressChangeEnd(
              sliderValue: value,
              mode: mode,
              viewState: viewState,
            ),
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
