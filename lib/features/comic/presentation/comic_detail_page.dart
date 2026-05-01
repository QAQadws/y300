import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/presentation/controllers/comic_detail_controller.dart';

class ComicDetailPage extends ConsumerWidget {
  const ComicDetailPage({
    super.key,
    required this.comicId,
  });

  final String comicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      comicDetailControllerProvider(ComicDetailArgs(comicId: comicId)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画详情'),
        actions: [
          IconButton(
            key: const Key('comic-detail-refresh-button'),
            tooltip: '刷新章节',
            onPressed: () {
              ref
                  .read(comicDetailControllerProvider(ComicDetailArgs(comicId: comicId)).notifier)
                  .refreshEpisodes();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载漫画详情失败：$error', textAlign: TextAlign.center),
          ),
        ),
        data: (viewState) {
          final detail = viewState.detail;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 108,
                      height: 144,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: detail.coverImageUrl == null
                            ? Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.image_not_supported_outlined),
                              )
                            : Image.network(
                                detail.coverImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.broken_image_outlined),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text('作者：${detail.author ?? '未知'}'),
                          const SizedBox(height: 4),
                          Text('章节数：${detail.episodeCount}'),
                          const SizedBox(height: 4),
                          Text('来源Tid：${detail.sourceTid}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (viewState.refreshHint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      viewState.refreshHint!,
                      key: const Key('comic-detail-refresh-hint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: viewState.episodes.isEmpty
                    ? const Center(child: Text('暂无章节，点击右上角刷新章节'))
                    : ListView.separated(
                        key: const Key('comic-detail-episode-list'),
                        itemCount: viewState.episodes.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final episode = viewState.episodes[index];
                          return ListTile(
                            title: Text(episode.episodeTitle?.trim().isNotEmpty == true
                                ? episode.episodeTitle!
                                : '章节 ${episode.sourceTid}'),
                            subtitle: Text('Tid: ${episode.sourceTid}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _ComicReaderPlaceholderPage(
                                    comicId: comicId,
                                    episodeId: episode.episodeId,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              if (viewState.isRefreshing)
                const LinearProgressIndicator(
                  key: Key('comic-detail-refresh-progress'),
                  minHeight: 2,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ComicReaderPlaceholderPage extends StatelessWidget {
  const _ComicReaderPlaceholderPage({
    required this.comicId,
    required this.episodeId,
  });

  final String comicId;
  final String episodeId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画阅读')),
      body: Center(
        child: Text('阶段5实现阅读器\ncomicId=$comicId\nepisodeId=$episodeId', textAlign: TextAlign.center),
      ),
    );
  }
}
