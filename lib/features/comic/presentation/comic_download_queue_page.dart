import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';

class ComicDownloadQueuePage extends ConsumerWidget {
  const ComicDownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(comicDownloadQueueProvider);
    final snapshot = ref.watch(comicDownloadQueueSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('下载队列')),
      body: ValueListenableBuilder<ComicDownloadQueueSnapshot>(
        valueListenable: snapshot,
        builder: (context, value, _) {
          if (value.isEmpty) {
            return const Center(
              key: Key('comic-download-queue-empty'),
              child: Text('暂无下载任务'),
            );
          }
          final active = value.activeEntry;
          final pending = value.entries
              .where(
                (entry) => entry.status == ComicDownloadQueueStatus.pending,
              )
              .toList(growable: false);
          final failed = value.entries
              .where((entry) => entry.status == ComicDownloadQueueStatus.failed)
              .toList(growable: false);
          return ListView(
            key: const Key('comic-download-queue-list'),
            children: [
              if (active != null) ...[
                const _QueueSectionTitle('正在下载'),
                _ActiveDownloadTile(
                  entry: active,
                  onCancel: () => _runAction(
                    context,
                    action: () => queue.cancel(active.id),
                    failurePrefix: '取消下载失败',
                  ),
                ),
              ],
              if (pending.isNotEmpty) ...[
                const _QueueSectionTitle('等待中'),
                for (var index = 0; index < pending.length; index++)
                  _PendingDownloadTile(
                    entry: pending[index],
                    position: index + 1,
                    onRemove: () => _runAction(
                      context,
                      action: () => queue.remove(pending[index].id),
                      failurePrefix: '移除任务失败',
                    ),
                  ),
              ],
              if (failed.isNotEmpty) ...[
                const _QueueSectionTitle('下载失败'),
                for (final entry in failed)
                  _FailedDownloadTile(
                    entry: entry,
                    onRetry: () => _runAction(
                      context,
                      action: () => queue.retry(entry.id),
                      failurePrefix: '重试失败',
                    ),
                    onRemove: () => _runAction(
                      context,
                      action: () => queue.remove(entry.id),
                      failurePrefix: '移除任务失败',
                    ),
                  ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context, {
    required Future<void> Function() action,
    required String failurePrefix,
  }) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$failurePrefix：$error')));
    }
  }
}

class _QueueSectionTitle extends StatelessWidget {
  const _QueueSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _ActiveDownloadTile extends StatelessWidget {
  const _ActiveDownloadTile({required this.entry, required this.onCancel});

  final ComicDownloadQueueEntry entry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final canceling = entry.status == ComicDownloadQueueStatus.cancelRequested;
    return Padding(
      key: ValueKey<String>('comic-download-active-${entry.id}'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.comicTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.episodeTitle} · '
                      '${canceling ? '正在取消' : _progressLabel(entry)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey<String>('comic-download-cancel-${entry.id}'),
                tooltip: canceling ? '正在取消' : '取消下载',
                onPressed: canceling ? null : onCancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            key: ValueKey<String>('comic-download-progress-${entry.id}'),
            value: _progressValue(entry),
          ),
        ],
      ),
    );
  }
}

class _PendingDownloadTile extends StatelessWidget {
  const _PendingDownloadTile({
    required this.entry,
    required this.position,
    required this.onRemove,
  });

  final ComicDownloadQueueEntry entry;
  final int position;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('comic-download-pending-${entry.id}'),
      title: Text(
        entry.comicTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${entry.episodeTitle} · 第 $position 位'),
      trailing: IconButton(
        key: ValueKey<String>('comic-download-remove-${entry.id}'),
        tooltip: '移除任务',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _FailedDownloadTile extends StatelessWidget {
  const _FailedDownloadTile({
    required this.entry,
    required this.onRetry,
    required this.onRemove,
  });

  final ComicDownloadQueueEntry entry;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('comic-download-failed-${entry.id}'),
      title: Text(
        entry.comicTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.episodeTitle} · ${entry.lastError ?? '下载失败'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey<String>('comic-download-retry-${entry.id}'),
            tooltip: '重试',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: ValueKey<String>('comic-download-remove-${entry.id}'),
            tooltip: '移除任务',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

String _progressLabel(ComicDownloadQueueEntry entry) {
  final total = entry.totalImages;
  return total == null || total <= 0
      ? '正在解析图片'
      : '${entry.completedImages}/$total';
}

double? _progressValue(ComicDownloadQueueEntry entry) {
  final total = entry.totalImages;
  if (total == null || total <= 0) {
    return null;
  }
  return (entry.completedImages / total).clamp(0.0, 1.0).toDouble();
}
