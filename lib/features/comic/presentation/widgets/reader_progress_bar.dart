import 'package:flutter/material.dart';

import 'package:y300/features/comic/domain/services/comic_reader_chapter_preload.dart';

/// Reusable reader progress control.
///
/// Layout contract:
/// - Left/Right outer buttons are chapter navigation actions.
/// - Inner capsule contains current page, slider and total page labels.
class ReaderProgressBar extends StatelessWidget {
  const ReaderProgressBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    required this.nextChapterPreload,
    required this.onPreviousEpisode,
    required this.onNextEpisode,
    required this.onChanged,
    required this.onChangeEnd,
    this.onChangeStart,
    this.interactionLocked = false,
  });

  final int currentPage;
  final int totalPages;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final ComicReaderChapterPreloadState nextChapterPreload;
  final VoidCallback onPreviousEpisode;
  final VoidCallback onNextEpisode;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChangeStart;
  final bool interactionLocked;

  @override
  Widget build(BuildContext context) {
    final safeTotal = totalPages < 1 ? 1 : totalPages;
    final current = currentPage.clamp(1, safeTotal);
    final sliderValue = (current - 1).toDouble();
    final maxValue = (safeTotal - 1).toDouble();

    return Row(
      children: [
        IconButton(
          key: const Key('comic-reader-prev-episode-button'),
          tooltip: '上一话',
          onPressed: hasPreviousEpisode ? onPreviousEpisode : null,
          icon: const Icon(Icons.skip_previous),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '$current',
                    key: const Key('comic-reader-current-page-label'),
                    textAlign: TextAlign.left,
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('comic-reader-progress-slider'),
                    value: sliderValue,
                    min: 0,
                    max: maxValue,
                    divisions: safeTotal > 1 ? safeTotal - 1 : null,
                    onChangeStart: interactionLocked ? null : onChangeStart,
                    onChanged: interactionLocked ? null : onChanged,
                    onChangeEnd: interactionLocked ? null : onChangeEnd,
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$safeTotal',
                    key: const Key('comic-reader-total-page-label'),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const Key('comic-reader-next-episode-button'),
          tooltip: _nextEpisodeTooltip(),
          onPressed: hasNextEpisode ? onNextEpisode : null,
          icon: Icon(_nextEpisodeIcon()),
        ),
      ],
    );
  }

  IconData _nextEpisodeIcon() {
    switch (nextChapterPreload.status) {
      case ComicReaderChapterPreloadStatus.loadingImages:
      case ComicReaderChapterPreloadStatus.preloadingPages:
        return Icons.downloading_outlined;
      case ComicReaderChapterPreloadStatus.ready:
        return Icons.offline_bolt_outlined;
      case ComicReaderChapterPreloadStatus.failed:
        return Icons.error_outline;
      case ComicReaderChapterPreloadStatus.unavailable:
      case ComicReaderChapterPreloadStatus.idle:
      case ComicReaderChapterPreloadStatus.imagesReady:
        return Icons.skip_next;
    }
  }

  String _nextEpisodeTooltip() {
    if (!hasNextEpisode) {
      return '已是最后一话';
    }
    switch (nextChapterPreload.status) {
      case ComicReaderChapterPreloadStatus.loadingImages:
      case ComicReaderChapterPreloadStatus.preloadingPages:
        return '下一话预加载中';
      case ComicReaderChapterPreloadStatus.ready:
        return '下一话已预加载';
      case ComicReaderChapterPreloadStatus.failed:
        return '下一话预加载失败，点击加载';
      case ComicReaderChapterPreloadStatus.unavailable:
      case ComicReaderChapterPreloadStatus.idle:
      case ComicReaderChapterPreloadStatus.imagesReady:
        return '下一话';
    }
  }
}
