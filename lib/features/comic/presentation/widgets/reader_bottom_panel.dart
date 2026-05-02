import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';

class ReaderBottomPanel extends StatelessWidget {
  const ReaderBottomPanel({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    required this.onPreviousEpisode,
    required this.onNextEpisode,
  });

  final ReaderModePreference currentMode;
  final ValueChanged<ReaderModePreference> onModeChanged;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final VoidCallback onPreviousEpisode;
  final VoidCallback onNextEpisode;

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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('comic-reader-prev-episode-button'),
                      onPressed: hasPreviousEpisode ? onPreviousEpisode : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('上一话'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('comic-reader-next-episode-button'),
                      onPressed: hasNextEpisode ? onNextEpisode : null,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('下一话'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
