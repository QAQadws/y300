import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/widgets/reader_progress_bar.dart';

class ReaderBottomPanel extends StatelessWidget {
  const ReaderBottomPanel({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.currentPage,
    required this.totalPages,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    required this.onPreviousEpisode,
    required this.onNextEpisode,
    required this.onProgressChanged,
    required this.onProgressChangeEnd,
  });

  final ReaderModePreference currentMode;
  final ValueChanged<ReaderModePreference> onModeChanged;
  final int currentPage;
  final int totalPages;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final VoidCallback onPreviousEpisode;
  final VoidCallback onNextEpisode;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onProgressChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReaderProgressBar(
                currentPage: currentPage,
                totalPages: totalPages,
                hasPreviousEpisode: hasPreviousEpisode,
                hasNextEpisode: hasNextEpisode,
                onPreviousEpisode: onPreviousEpisode,
                onNextEpisode: onNextEpisode,
                onChanged: onProgressChanged,
                onChangeEnd: onProgressChangeEnd,
              ),
              const SizedBox(height: 10),
              SegmentedButton<ReaderModePreference>(
                key: const Key('comic-reader-mode-switch'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ReaderModePreference.vertical,
                    icon: Icon(Icons.view_stream_outlined),
                    label: Text('垂直'),
                  ),
                  ButtonSegment(
                    value: ReaderModePreference.ltr,
                    icon: Icon(Icons.swipe_left_outlined),
                    label: Text('左到右'),
                  ),
                  ButtonSegment(
                    value: ReaderModePreference.rtl,
                    icon: Icon(Icons.swipe_right_outlined),
                    label: Text('右到左'),
                  ),
                ],
                selected: {currentMode},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    onModeChanged(selection.first);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
