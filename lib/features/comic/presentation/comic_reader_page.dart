import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/comic/presentation/providers/reader_preferences_provider.dart';

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

  // Reader menu visibility is independent from image rendering.
  // This separation keeps gesture interaction decoupled from content logic.
  bool _isMenuVisible = false;
  late final AnimationController _menuAnimationController;
  late final Animation<Offset> _topMenuSlideAnimation;
  late final Animation<Offset> _bottomMenuSlideAnimation;

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
    ).animate(CurvedAnimation(parent: _menuAnimationController, curve: Curves.easeOutCubic));
    _bottomMenuSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _menuAnimationController, curve: Curves.easeOutCubic));
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
    // Phase-0 preload: preferences are introduced now and will be consumed
    // by phase-2/3 UI features without changing this page's external contract.
    ref.watch(readerPreferencesControllerProvider);

    final state = ref.watch(
      comicReaderControllerProvider(
        ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId),
      ),
    );

    return Scaffold(
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('加载阅读器失败：$error')),
        data: (viewState) {
          if (viewState.images.isEmpty) {
            return const Center(child: Text('当前章节没有可阅读图片'));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients && _scrollController.offset == 0 && viewState.lastScrollOffset > 0) {
              _scrollController.jumpTo(viewState.lastScrollOffset);
            }
          });

          return Stack(
            children: [
              _buildReaderContentLayer(viewState),
              _buildCenterTapOverlay(),
              _buildReaderTopOverlayLayer(viewState),
              _buildReaderBottomOverlayLayer(viewState),
            ],
          );
        },
      ),
    );
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
    final state = ref.read(
      comicReaderControllerProvider(
        ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId),
      ),
    );
    final total = state.value?.images.length ?? 0;
    if (total == 0) {
      return;
    }
    final index = ((total - 1) * ratio).round();
    if (index != _lastKnownIndex) {
      _lastKnownIndex = index;
      ref
          .read(
            comicReaderControllerProvider(
              ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId),
            ).notifier,
          )
          .onScrollProgress(currentIndex: index, scrollOffset: position.pixels);
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
            child: Text(viewState.hint!, style: Theme.of(context).textTheme.bodySmall),
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
                              onPressed: () {
                                ref
                                    .read(
                                      comicReaderControllerProvider(
                                        ComicReaderArgs(
                                          comicId: widget.comicId,
                                          episodeId: widget.episodeId,
                                        ),
                                      ).notifier,
                                    )
                                    .retryImage(image.imageUrl);
                              },
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

  Widget _buildCenterTapOverlay() {
    // Only center area toggles menus, matching the expected reader behavior.
    // We intentionally keep side areas non-intercepting for future page-turn
    // gesture zoning in phase-2.
    return Positioned.fill(
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          Expanded(
            child: GestureDetector(
              key: const Key('comic-reader-center-tap-zone'),
              behavior: HitTestBehavior.translucent,
              onTap: _toggleReaderMenu,
              child: const SizedBox.expand(),
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
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
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('comic-reader-top-back-button'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        viewState.episodeTitle,
                        key: const Key('comic-reader-top-episode-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: const Key('comic-reader-cache-episode'),
                      tooltip: '缓存本话',
                      onPressed: () {
                        ref
                            .read(
                              comicReaderControllerProvider(
                                ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId),
                              ).notifier,
                            )
                            .cacheCurrentEpisode();
                      },
                      icon: const Icon(Icons.download_for_offline_outlined),
                    ),
                    IconButton(
                      key: const Key('comic-reader-cache-unread'),
                      tooltip: '缓存全部未读',
                      onPressed: () {
                        ref
                            .read(
                              comicReaderControllerProvider(
                                ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId),
                              ).notifier,
                            )
                            .cacheAllUnread();
                      },
                      icon: const Icon(Icons.download_done_outlined),
                    ),
                  ],
                ),
              ),
            ),
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
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('comic-reader-prev-episode-button'),
                        onPressed: viewState.hasPreviousEpisode
                            ? () => Navigator.of(context).pop('previous')
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('上一话'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('comic-reader-next-episode-button'),
                        onPressed: viewState.hasNextEpisode
                            ? () => Navigator.of(context).pop('next')
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('下一话'),
                      ),
                    ),
                  ],
                ),
              ),
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
