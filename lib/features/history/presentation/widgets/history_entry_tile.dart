import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/presentation/widgets/history_thumbnail.dart';

typedef HistoryThumbnailBuilder =
    Widget Function(BuildContext context, HistoryEntry entry);

class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onDelete,
    this.headerBuilder,
    this.thumbnailBuilder,
  });

  final HistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final ImageRequestHeaderBuilder? headerBuilder;
  final HistoryThumbnailBuilder? thumbnailBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localTime = entry.lastVisitedAt.toLocal();
    final timeText =
        '${_twoDigits(localTime.hour)}:${_twoDigits(localTime.minute)}';
    final typeLabel = switch (entry.target.type) {
      HistoryTargetType.thread => '帖子',
      HistoryTargetType.comic => '漫画',
      HistoryTargetType.novel => '小说',
    };
    final semanticsLabel =
        '$typeLabel，${entry.title}，${entry.contextLabel}，$timeText';

    const borderRadius = BorderRadius.all(Radius.circular(8));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        key: ValueKey<String>('history-entry-surface-${entry.target}'),
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: semanticsLabel,
          child: InkWell(
            key: ValueKey<String>('history-entry-open-${entry.target}'),
            onTap: onOpen,
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child:
                        thumbnailBuilder?.call(context, entry) ??
                        HistoryThumbnail(
                          entry: entry,
                          headerBuilder: headerBuilder,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${entry.contextLabel} · $timeText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>(
                      'history-entry-delete-${entry.target}',
                    ),
                    tooltip: '删除记录',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
