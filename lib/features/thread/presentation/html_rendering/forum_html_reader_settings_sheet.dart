import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

class ForumHtmlReaderSettingsSheet extends ConsumerWidget {
  const ForumHtmlReaderSettingsSheet({
    super.key,
    this.showConversionControls = false,
    this.showAuthorStyleControls = true,
    this.showResetButton = true,
  });

  final bool showConversionControls;
  final bool showAuthorStyleControls;
  final bool showResetButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(forumHtmlReaderPreferencesControllerProvider).value ??
        ForumHtmlReaderPreferences.defaults();
    final controller = ref.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    );
    final typography = preferences.typography;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
            if (showConversionControls) ...[
              _ConversionModeSegmentedControl(
                mode: preferences.conversionMode,
                onChanged: controller.setConversionMode,
              ),
              const SizedBox(height: 8),
            ],
            _TypographySlider(
              key: const Key('forum-html-reader-font-scale-slider'),
              label: '字号',
              value: typography.fontScale,
              min: 0.7,
              max: 2.0,
              divisions: 26,
              display: '${(typography.fontScale * 100).round()}%',
              onChanged: controller.setFontScale,
            ),
            _TypographySlider(
              key: const Key('forum-html-reader-line-height-slider'),
              label: '间隔',
              value: typography.lineHeightScale,
              min: 1.0,
              max: 2.5,
              divisions: 30,
              display: '${typography.lineHeightScale.toStringAsFixed(1)}×',
              onChanged: controller.setLineHeightScale,
            ),
            if (showAuthorStyleControls) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('forum-html-reader-preserve-font-size-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('保留作者字号'),
                value: preferences.preserveAuthorFontSize,
                onChanged: controller.setPreserveAuthorFontSize,
              ),
              SwitchListTile(
                key: const Key('forum-html-reader-preserve-color-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('保留作者颜色'),
                value: preferences.preserveAuthorColor,
                onChanged: controller.setPreserveAuthorColor,
              ),
              SwitchListTile(
                key: const Key('forum-html-reader-preserve-background-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('保留作者背景'),
                value: preferences.preserveAuthorBackground,
                onChanged: controller.setPreserveAuthorBackground,
              ),
            ],
            if (showResetButton) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  key: const Key('forum-html-reader-reset-button'),
                  onPressed: () => controller.reset(),
                  child: const Text('恢复默认'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversionModeSegmentedControl extends StatelessWidget {
  const _ConversionModeSegmentedControl({
    required this.mode,
    required this.onChanged,
  });

  final TextConversionMode mode;
  final Future<void> Function(TextConversionMode mode) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TextConversionMode>(
        key: const Key('forum-html-reader-conversion-mode-control'),
        segments: const [
          ButtonSegment(
            value: TextConversionMode.none,
            label: Text('原文', key: Key('forum-html-reader-conversion-none')),
          ),
          ButtonSegment(
            value: TextConversionMode.toSimplified,
            label: Text(
              '简体',
              key: Key('forum-html-reader-conversion-simplified'),
            ),
          ),
          ButtonSegment(
            value: TextConversionMode.toTraditional,
            label: Text(
              '繁体',
              key: Key('forum-html-reader-conversion-traditional'),
            ),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) {
          unawaited(onChanged(selection.single));
        },
      ),
    );
  }
}

class _TypographySlider extends StatelessWidget {
  const _TypographySlider({
    super.key,
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
          width: 48,
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

extension ForumHtmlReaderPreferencesDebugLabel on ForumHtmlReaderPreferences {
  String get typographyDebugLabel {
    return '字号 ${(typography.fontScale * 100).round()}% / '
        '间隔 ${typography.lineHeightScale.toStringAsFixed(1)}×';
  }

  String get authorStyleDebugLabel {
    return '作者样式：字号${_yesNo(preserveAuthorFontSize)} / '
        '颜色${_yesNo(preserveAuthorColor)} / '
        '背景${_yesNo(preserveAuthorBackground)}';
  }

  String _yesNo(bool value) => value ? '保留' : '忽略';
}
