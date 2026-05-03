import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_detail_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';

class NovelDetailPage extends ConsumerWidget {
  const NovelDetailPage({
    super.key,
    required this.novelId,
  });

  final String novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      novelDetailControllerProvider(NovelDetailArgs(novelId: novelId)),
    );
    final controller = ref.read(
      novelDetailControllerProvider(NovelDetailArgs(novelId: novelId)).notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('小说详情'),
        actions: [
          IconButton(
            key: const Key('novel-detail-refresh-button'),
            tooltip: '刷新章节',
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.refreshEpisodes(),
          ),
          IconButton(
            key: const Key('novel-detail-sort-button'),
            tooltip: '切换排序',
            icon: Icon(
              state.asData?.value.sortDescending == true
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
            ),
            onPressed: () => controller.toggleSortOrder(),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('加载小说详情失败：$error', textAlign: TextAlign.center),
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
                                child: const Icon(Icons.menu_book_outlined),
                              )
                            : Image.network(
                                detail.coverImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(detail.title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text('作者：${detail.author ?? '未知'}'),
                          const SizedBox(height: 4),
                          Text('版块：${detail.sourceFid}'),
                          const SizedBox(height: 4),
                          Text('来源Tid：${detail.sourceTid}'),
                          const SizedBox(height: 4),
                          Text('章节数：${detail.episodeCount}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (viewState.hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      viewState.hint!,
                      key: const Key('novel-detail-refresh-hint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    viewState.sortDescending ? '排序：降序' : '排序：升序',
                    key: const Key('novel-detail-sort-hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: viewState.episodes.isEmpty
                    ? const Center(child: Text('暂无章节，请点击右上角刷新'))
                    : ListView.separated(
                        key: const Key('novel-detail-episode-list'),
                        itemCount: viewState.episodes.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final episode = viewState.episodes[index];
                          return ListTile(
                            title: Text(episode.episodeTitle),
                            subtitle: Text(
                              'PID:${episode.sourcePid ?? '-'}  Page:${episode.sourcePage ?? '-'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openReader(context, episode),
                          );
                        },
                      ),
              ),
              if (viewState.isRefreshing)
                const LinearProgressIndicator(
                  key: Key('novel-detail-refresh-progress'),
                  minHeight: 2,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openReader(BuildContext context, NovelEpisodeItem episode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NovelReaderPage(
          novelId: episode.novelId,
          initialEpisodeId: episode.episodeId,
        ),
      ),
    );
  }
}
