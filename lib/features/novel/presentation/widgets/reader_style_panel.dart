import 'package:flutter/material.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';

class ReaderStylePanel extends StatelessWidget {
  const ReaderStylePanel({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
  });

  final NovelReaderPreferences preferences;
  final ValueChanged<NovelReaderPreferences> onPreferencesChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSlider(
            context: context,
            label: '字号',
            value: preferences.fontSize,
            min: 14,
            max: 30,
            onChanged: (value) => onPreferencesChanged(preferences.copyWith(fontSize: value)),
          ),
          _buildSlider(
            context: context,
            label: '行距',
            value: preferences.lineHeight,
            min: 1.2,
            max: 2.4,
            onChanged: (value) => onPreferencesChanged(preferences.copyWith(lineHeight: value)),
          ),
          _buildSlider(
            context: context,
            label: '段距',
            value: preferences.paragraphSpacing,
            min: 0,
            max: 24,
            onChanged: (value) => onPreferencesChanged(preferences.copyWith(paragraphSpacing: value)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('主题：'),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const Key('novel-theme-light'),
                label: const Text('浅色'),
                selected: preferences.themeMode == 'light',
                onSelected: (_) => onPreferencesChanged(preferences.copyWith(themeMode: 'light')),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const Key('novel-theme-sepia'),
                label: const Text('护眼'),
                selected: preferences.themeMode == 'sepia',
                onSelected: (_) => onPreferencesChanged(preferences.copyWith(themeMode: 'sepia')),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                key: const Key('novel-theme-dark'),
                label: const Text('深色'),
                selected: preferences.themeMode == 'dark',
                onSelected: (_) => onPreferencesChanged(preferences.copyWith(themeMode: 'dark')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
