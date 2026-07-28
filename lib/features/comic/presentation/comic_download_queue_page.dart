import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/presentation/comic_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/l10n/app_localizations.dart';

class ComicDownloadQueuePage extends ConsumerWidget {
  const ComicDownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(comicDownloadQueueProvider);
    final snapshot = ref.watch(comicDownloadQueueSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.comicDownloadQueue)),
      body: ValueListenableBuilder<ComicDownloadQueueSnapshot>(
        valueListenable: snapshot,
        builder: (context, value, _) {
          if (value.isEmpty) {
            return Center(
              key: const Key('comic-download-queue-empty'),
              child: Text(l10n.comicDownloadQueueEmpty),
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
                _QueueSectionTitle(l10n.comicDownloadActive),
                _ActiveDownloadTile(
                  entry: active,
                  onCancel: () => _runAction(
                    context,
                    action: () => queue.cancel(active.id),
                    failureMessage: (error) => l10n.comicDownloadCancelFailed(
                      LibraryErrorSummary.resolve(l10n, error),
                    ),
                  ),
                ),
              ],
              if (pending.isNotEmpty) ...[
                _QueueSectionTitle(l10n.comicDownloadPending),
                for (var index = 0; index < pending.length; index++)
                  _PendingDownloadTile(
                    entry: pending[index],
                    position: index + 1,
                    onRemove: () => _runAction(
                      context,
                      action: () => queue.remove(pending[index].id),
                      failureMessage: (error) => l10n.comicDownloadRemoveFailed(
                        LibraryErrorSummary.resolve(l10n, error),
                      ),
                    ),
                  ),
              ],
              if (failed.isNotEmpty) ...[
                _QueueSectionTitle(l10n.comicDownloadFailedSection),
                for (final entry in failed)
                  _FailedDownloadTile(
                    entry: entry,
                    onRetry: () => _runAction(
                      context,
                      action: () => queue.retry(entry.id),
                      failureMessage: (error) => l10n.comicDownloadRetryFailed(
                        LibraryErrorSummary.resolve(l10n, error),
                      ),
                    ),
                    onRemove: () => _runAction(
                      context,
                      action: () => queue.remove(entry.id),
                      failureMessage: (error) => l10n.comicDownloadRemoveFailed(
                        LibraryErrorSummary.resolve(l10n, error),
                      ),
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
    required String Function(Object error) failureMessage,
  }) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failureMessage(error))));
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
    final l10n = AppLocalizations.of(context);
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
                      ComicTextResolver.workTitle(
                        l10n,
                        entry.comicTitle,
                        entry.comicId,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ComicTextResolver.chapterTitle(l10n, entry.episodeTitle, entry.sourceTid)} · '
                      '${canceling ? l10n.comicDownloadCanceling : _progressLabel(l10n, entry)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey<String>('comic-download-cancel-${entry.id}'),
                tooltip: canceling
                    ? l10n.comicDownloadCanceling
                    : l10n.comicDownloadCancel,
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
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: ValueKey<String>('comic-download-pending-${entry.id}'),
      title: Text(
        ComicTextResolver.workTitle(l10n, entry.comicTitle, entry.comicId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.comicDownloadQueuePosition(
          ComicTextResolver.chapterTitle(
            l10n,
            entry.episodeTitle,
            entry.sourceTid,
          ),
          position,
        ),
      ),
      trailing: IconButton(
        key: ValueKey<String>('comic-download-remove-${entry.id}'),
        tooltip: l10n.comicDownloadRemove,
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
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: ValueKey<String>('comic-download-failed-${entry.id}'),
      title: Text(
        ComicTextResolver.workTitle(l10n, entry.comicTitle, entry.comicId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.comicDownloadFailureDetail(
          ComicTextResolver.chapterTitle(
            l10n,
            entry.episodeTitle,
            entry.sourceTid,
          ),
          ComicTextResolver.downloadFailure(l10n, entry.failureCode),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey<String>('comic-download-retry-${entry.id}'),
            tooltip: l10n.comicDownloadRetry,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: ValueKey<String>('comic-download-remove-${entry.id}'),
            tooltip: l10n.comicDownloadRemove,
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

String _progressLabel(AppLocalizations l10n, ComicDownloadQueueEntry entry) {
  final total = entry.totalImages;
  return total == null || total <= 0
      ? l10n.comicDownloadResolvingImages
      : l10n.comicDownloadProgress(entry.completedImages, total);
}

double? _progressValue(ComicDownloadQueueEntry entry) {
  final total = entry.totalImages;
  if (total == null || total <= 0) {
    return null;
  }
  return (entry.completedImages / total).clamp(0.0, 1.0).toDouble();
}
