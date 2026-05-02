import 'package:flutter/material.dart';

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
    required this.onPreviousEpisode,
    required this.onNextEpisode,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int currentPage;
  final int totalPages;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final VoidCallback onPreviousEpisode;
  final VoidCallback onNextEpisode;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

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
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
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
          tooltip: '下一话',
          onPressed: hasNextEpisode ? onNextEpisode : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}
