import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';

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
  int _lastKnownIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      comicReaderControllerProvider(
        ComicReaderArgs(comicId: widget.comicId, episodeId: widget.episodeId),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画阅读'),
        actions: [
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
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
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
}
