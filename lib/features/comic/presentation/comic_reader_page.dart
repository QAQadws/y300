import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
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
  int _lastKnownIndex = 0;

  bool _isMenuVisible = false;
  late final AnimationController _menuAnimationController;
  late final Animation<Offset> _topMenuSlideAnimation;
  late final Animation<Offset> _bottomMenuSlideAnimation;

  ComicReaderArgs get _readerArgs =>
      ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
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
      ..removeListener(_onScroll)
      ..dispose();
    _menuAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readerPreferencesControllerProvider);

    final state = ref.watch(
      comicReaderControllerProvider(_readerArgs),
    );

    return Scaffold(
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('加载阅读器失败：$error')),
        data: (viewState) {
          if (viewState.images.isEmpty) {
            return const Center(child: Text('当前章节没有可阅读图片'));
          }

          _restoreScrollOffsetIfNeeded(viewState.lastScrollOffset);

          return Stack(
            children: [
              _buildReaderContentLayer(viewState),
              ReaderTapZones(onCenterTap: _toggleReaderMenu),
              _buildReaderTopOverlayLayer(viewState),
              _buildReaderBottomOverlayLayer(viewState),
            ],
          );
        },
      ),
    );
  }

  void _restoreScrollOffsetIfNeeded(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      if (_scrollController.offset == 0 && offset > 0) {
        _scrollController.jumpTo(offset);
      }
    });
  }

  ComicReaderController _controller() {
    return ref.read(comicReaderControllerProvider(_readerArgs).notifier);
  }

  void _onScroll() {
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

  Widget _buildReaderContentLayer(ComicReaderViewState viewState) {
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
          child: ListView.builder(
            key: const Key('comic-reader-image-list'),
            controller: _scrollController,
            itemCount: viewState.images.length,
            itemBuilder: (context, index) {
              final image = viewState.images[index];
              return Column(
                children: [
                  CachedNetworkImage(
                    imageUrl: image.imageUrl,
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
                              key: ValueKey<String>('comic-reader-retry-${image.imageUrl}'),
                              onPressed: () => _controller().retryImage(image.imageUrl),
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
            },
          ),
        ),
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

  Widget _buildReaderBottomOverlayLayer(ComicReaderViewState viewState) {
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
            hasPreviousEpisode: viewState.hasPreviousEpisode,
            hasNextEpisode: viewState.hasNextEpisode,
            onPreviousEpisode: () => Navigator.of(context).pop('previous'),
            onNextEpisode: () => Navigator.of(context).pop('next'),
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
