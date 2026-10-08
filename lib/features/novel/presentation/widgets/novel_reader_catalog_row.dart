import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_chapter_tile.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_chapter_progress_projector.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A catalog projection of the same chapter state shown on the work detail.
class NovelReaderCatalogRow extends StatelessWidget {
  const NovelReaderCatalogRow({
    super.key,
    required this.episode,
    required this.currentEpisodeId,
    required this.onTap,
    this.readingState,
    this.readingProgress,
    this.progressSnapshot,
    this.bookmarkEpisodeIds = const <String>{},
    this.onLongPress,
    this.onToggleReadState,
    this.readStateMutationLocked = false,
  });

  final NovelEpisodeItem episode;
  final String currentEpisodeId;
  final NovelReadingStateSnapshot? readingState;
  final NovelReadingProgress? readingProgress;
  final NovelReaderProgressSnapshot? progressSnapshot;
  final Set<String> bookmarkEpisodeIds;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Future<void> Function()? onToggleReadState;
  final bool readStateMutationLocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = readingState?.novelId == episode.novelId
        ? readingState
        : null;
    final episodeState = state?.episodeStates[episode.episodeId];
    final isRead = episodeState?.isRead == true;
    final isCurrent = episode.episodeId == currentEpisodeId;
    final isBookmarked =
        episodeState?.isBookmarked == true ||
        bookmarkEpisodeIds.contains(episode.episodeId);
    final progress = NovelChapterProgressProjector.project(
      novelId: episode.novelId,
      episodeId: episode.episodeId,
      progress: state == null
          ? readingProgress
          : state.progressByEpisode[episode.episodeId],
      isRecentChapter: state == null
          ? null
          : state.recentEpisodeId == episode.episodeId,
      liveSnapshot: isCurrent ? progressSnapshot : null,
    );
    final subtitle = LibraryDetailTextResolver.chapterSubtitle(
      l10n,
      subtitle: episode.datelineText ?? '',
      progress: progress,
      isRead: isRead,
    );
    final tile = ListTile(
      key: Key('novel-reader-chapter-${episode.episodeId}'),
      selected: isCurrent,
      leading: Icon(
        key: isBookmarked
            ? Key('novel-reader-chapter-bookmark-${episode.episodeId}')
            : null,
        semanticLabel: isBookmarked ? l10n.novelBookmark : null,
        isBookmarked
            ? Icons.bookmark
            : isCurrent
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(
        NovelTextResolver.chapterTitle(
          l10n,
          episode.episodeTitle,
          episode.sourceTid,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isRead
            ? theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: isRead
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant.withAlpha(170),
                    )
                  : null,
            ),
      trailing: !isCurrent
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                l10n.novelCurrent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
    final toggle = onToggleReadState;
    if (toggle == null) return tile;
    final foreground = isRead
        ? scheme.onSecondaryContainer
        : scheme.onPrimaryContainer;
    return LibraryChapterReadStateSwipe(
      key: Key('novel-reader-chapter-read-swipe-${episode.episodeId}'),
      foregroundKey: Key(
        'novel-reader-chapter-read-swipe-foreground-${episode.episodeId}',
      ),
      locked: readStateMutationLocked,
      onTriggered: toggle,
      background: ColoredBox(
        color: isRead ? scheme.secondaryContainer : scheme.primaryContainer,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  isRead ? Icons.remove_done : Icons.done,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isRead
                          ? l10n.libraryChapterClearReadState
                          : l10n.libraryChapterMarkRead,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: tile,
    );
  }
}
