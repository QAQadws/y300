import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

class UnifiedDetailChapterTile extends StatelessWidget {
  const UnifiedDetailChapterTile({
    super.key,
    required this.tileKey,
    required this.chapter,
    required this.subtitle,
    required this.showInlineProgress,
    required this.isDownloading,
    required this.downloadIconSize,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleDownload,
  });

  final Key tileKey;
  final LibraryChapterItem chapter;
  final String subtitle;
  final bool showInlineProgress;
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
    final hasStatus =
        (chapter.progressInfo != null && !showInlineProgress) ||
        chapter.isDownloaded ||
        chapter.isRead;

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
                      progress: showInlineProgress
                          ? chapter.progressInfo
                          : null,
                      style:
                          theme.textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ) ??
                          TextStyle(color: subtitleColor),
                    ),
                    if (hasStatus) ...[
                      const SizedBox(height: 7),
                      _ChapterStatusRow(
                        chapter: chapter,
                        showProgress: !showInlineProgress,
                      ),
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
  const _ChapterStatusRow({required this.chapter, required this.showProgress});

  final LibraryChapterItem chapter;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (showProgress && chapter.progressInfo != null)
        _ChapterProgressBadge(
          key: ValueKey<String>(
            'unified-detail-chapter-progress-${chapter.episodeId}',
          ),
          progress: chapter.progressInfo!,
        ),
      if (chapter.isDownloaded)
        _DetailStatusBadge(
          key: ValueKey<String>(
            'unified-detail-chapter-downloaded-badge-${chapter.episodeId}',
          ),
          icon: Icons.check_circle_outline,
          label: '已下载',
          tone: _DetailStatusBadgeTone.success,
        ),
      if (chapter.isRead)
        _DetailStatusBadge(
          key: ValueKey<String>(
            'unified-detail-chapter-read-badge-${chapter.episodeId}',
          ),
          icon: Icons.done,
          label: '已读',
          tone: _DetailStatusBadgeTone.muted,
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

class _ChapterProgressBadge extends StatelessWidget {
  const _ChapterProgressBadge({super.key, required this.progress});

  final LibraryChapterProgressInfo progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Text(
      progress.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
    final badge = Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withAlpha(64)),
      ),
      child: text,
    );

    final semanticLabel = progress.semanticLabel;
    if (semanticLabel == null || semanticLabel.isEmpty) {
      return badge;
    }
    return Semantics(label: semanticLabel, child: badge);
  }
}

enum _DetailStatusBadgeTone { success, muted }

class _DetailStatusBadge extends StatelessWidget {
  const _DetailStatusBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final _DetailStatusBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = switch (tone) {
      _DetailStatusBadgeTone.success => scheme.tertiary,
      _DetailStatusBadgeTone.muted => scheme.onSurfaceVariant,
    };

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
