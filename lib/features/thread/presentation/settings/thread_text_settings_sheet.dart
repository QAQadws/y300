import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/settings/thread_text_preferences_provider.dart';

/// Bottom sheet with three sliders for thread post body typography.
/// Changing a slider immediately persists and takes effect on the next build.
class ThreadTextSettingsSheet extends ConsumerWidget {
  const ThreadTextSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(threadTextPreferencesControllerProvider);
    final typography = prefsAsync.value?.typography ?? RichTextTypography.standard;
    final controller =
        ref.read(threadTextPreferencesControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _TypographySlider(
            label: '字号',
            value: typography.fontScale,
            min: 0.7,
            max: 2.0,
            divisions: 26,
            display: '${(typography.fontScale * 100).round()}%',
            onChanged: controller.setFontScale,
          ),
          _TypographySlider(
            label: '行距',
            value: typography.lineHeightScale,
            min: 1.0,
            max: 2.5,
            divisions: 30,
            display: '${typography.lineHeightScale.toStringAsFixed(1)}×',
            onChanged: controller.setLineHeightScale,
          ),
          _TypographySlider(
            label: '段距',
            value: typography.paragraphSpacing,
            min: 0.0,
            max: 40.0,
            divisions: 40,
            display: '${typography.paragraphSpacing.round()}px',
            onChanged: controller.setParagraphSpacing,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => controller.setTypography(RichTextTypography.standard),
              child: const Text('恢复默认'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypographySlider extends StatelessWidget {
  const _TypographySlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label, style: theme.textTheme.labelMedium),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            display,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
