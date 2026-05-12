import 'package:flutter/material.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/widgets/reader_progress_bar.dart';

class ReaderBottomPanel extends StatelessWidget {
  const ReaderBottomPanel({
    super.key,
    required this.currentMode,
    required this.currentPage,
    required this.totalPages,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    required this.onPreviousEpisode,
    required this.onNextEpisode,
    required this.onOpenModeSheet,
    required this.onOpenChapterList,
    required this.onOpenDisplaySettings,
    required this.onCacheEpisode,
    required this.onProgressChanged,
    required this.onProgressChangeEnd,
    this.onProgressChangeStart,
    this.isProgressInteractionLocked = false,
  });

  final ReaderModePreference currentMode;
  final int currentPage;
  final int totalPages;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final VoidCallback onPreviousEpisode;
  final VoidCallback onNextEpisode;
  final VoidCallback onOpenModeSheet;
  final VoidCallback onOpenChapterList;
  final VoidCallback onOpenDisplaySettings;
  final VoidCallback onCacheEpisode;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onProgressChangeEnd;
  final ValueChanged<double>? onProgressChangeStart;
  final bool isProgressInteractionLocked;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                onChangeStart: onProgressChangeStart,
                onChanged: onProgressChanged,
                onChangeEnd: onProgressChangeEnd,
                interactionLocked: isProgressInteractionLocked,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ReaderToolButton(
                    key: const Key('comic-reader-mode-switch'),
                    icon: _modeIcon(currentMode),
                    label: _modeLabel(currentMode),
                    onPressed: onOpenModeSheet,
                  ),
                  _ReaderToolButton(
                    key: const Key('comic-reader-chapter-list-button'),
                    icon: Icons.format_list_bulleted,
                    label: '章节',
                    onPressed: onOpenChapterList,
                  ),
                  _ReaderToolButton(
                    key: const Key('comic-reader-display-settings-button'),
                    icon: Icons.tune,
                    label: '显示',
                    onPressed: onOpenDisplaySettings,
                  ),
                  _ReaderToolButton(
                    key: const Key('comic-reader-bottom-cache-button'),
                    icon: Icons.download_for_offline_outlined,
                    label: '缓存',
                    onPressed: onCacheEpisode,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _modeIcon(ReaderModePreference mode) {
    switch (mode) {
      case ReaderModePreference.vertical:
        return Icons.view_stream_outlined;
      case ReaderModePreference.ltr:
        return Icons.swipe_left_outlined;
      case ReaderModePreference.rtl:
        return Icons.swipe_right_outlined;
    }
  }

  String _modeLabel(ReaderModePreference mode) {
    switch (mode) {
      case ReaderModePreference.vertical:
        return '垂直';
      case ReaderModePreference.ltr:
        return '左到右';
      case ReaderModePreference.rtl:
        return '右到左';
    }
  }
}

class _ReaderToolButton extends StatelessWidget {
  const _ReaderToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
