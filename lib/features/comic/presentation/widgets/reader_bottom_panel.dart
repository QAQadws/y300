import 'package:flutter/material.dart';

class ReaderBottomPanel extends StatelessWidget {
  const ReaderBottomPanel({
    super.key,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    required this.onPreviousEpisode,
    required this.onNextEpisode,
  });

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
          child: Row(
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
        ),
      ),
    );
  }
}
