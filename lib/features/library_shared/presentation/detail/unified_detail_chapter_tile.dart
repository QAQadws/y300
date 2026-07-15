import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

class UnifiedDetailChapterTile extends StatelessWidget {
  const UnifiedDetailChapterTile({
    super.key,
    required this.tileKey,
    required this.chapter,
    required this.subtitle,
    required this.isDownloading,
    required this.downloadIconSize,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleDownload,
  });

  final Key tileKey;
  final LibraryChapterItem chapter;
  final String subtitle;
  final bool isDownloading;
  final double downloadIconSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = chapter.isRead
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    final subtitleColor = chapter.isRead
        ? scheme.onSurfaceVariant.withAlpha(170)
        : scheme.onSurfaceVariant;
    final hasStatus = chapter.isDownloaded;

    return Material(
      key: tileKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (chapter.isBookmarked) ...[
                          Icon(
                            Icons.bookmark,
                            key: ValueKey<String>(
                              'unified-detail-chapter-bookmark-indicator-${chapter.episodeId}',
                            ),
                            size: 20,
                            color: scheme.primary,
                            semanticLabel: '已添加书签',
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            chapter.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: titleColor,
                              fontWeight: chapter.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ChapterSubtitle(
                      subtitle,
                      episodeId: chapter.episodeId,
                      progress: chapter.progressInfo,
                      style:
                          theme.textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ) ??
                          TextStyle(color: subtitleColor),
                    ),
                    if (hasStatus) ...[
                      const SizedBox(height: 7),
                      _ChapterStatusRow(chapter: chapter),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: chapter.isDownloaded ? '已下载，点击删除下载' : '下载该章节',
                iconSize: downloadIconSize,
                onPressed: isDownloading ? null : onToggleDownload,
                icon: isDownloading
                    ? SizedBox(
                        width: downloadIconSize,
                        height: downloadIconSize,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.2,
                        ),
                      )
                    : Icon(
                        chapter.isDownloaded
                            ? Icons.check_circle_outline
                            : Icons.arrow_circle_down,
                        size: downloadIconSize,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterStatusRow extends StatelessWidget {
  const _ChapterStatusRow({required this.chapter});

  final LibraryChapterItem chapter;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (chapter.isDownloaded)
        _DetailStatusBadge(
          key: ValueKey<String>(
            'unified-detail-chapter-downloaded-badge-${chapter.episodeId}',
          ),
          icon: Icons.check_circle_outline,
          label: '已下载',
        ),
    ];

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 6, runSpacing: 5, children: badges);
  }
}

class _ChapterSubtitle extends StatelessWidget {
  const _ChapterSubtitle(
    this.subtitle, {
    required this.episodeId,
    required this.progress,
    required this.style,
  });

  final String episodeId;
  final String subtitle;
  final LibraryChapterProgressInfo? progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    if (progress == null) {
      return Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final progressStyle = style.copyWith(
      color: (style.color ?? Theme.of(context).colorScheme.onSurfaceVariant)
          .withAlpha(150),
    );
    final text = RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: subtitle),
          const TextSpan(text: '  ·  '),
          TextSpan(text: progress.label, style: progressStyle),
        ],
      ),
    );
    return Semantics(
      key: ValueKey<String>(
        'unified-detail-chapter-inline-progress-$episodeId',
      ),
      label: '$subtitle，${progress.semanticLabel ?? progress.label}',
      child: ExcludeSemantics(child: text),
    );
  }
}

class _DetailStatusBadge extends StatelessWidget {
  const _DetailStatusBadge({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.tertiary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: foreground.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withAlpha(48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
