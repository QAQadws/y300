import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelReaderDisplaySettingsSheet extends StatelessWidget {
  const NovelReaderDisplaySettingsSheet({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
  });

  final NovelReaderPreferences preferences;
  final ValueChanged<NovelReaderPreferences> onPreferencesChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('novel-reader-display-settings-sheet'),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ReaderSheetTitle(title: '显示设置'),
          _SettingsSection(
            title: '排版',
            children: [
              _SettingsSlider(
                key: const Key('novel-reader-font-size-slider'),
                label: '字号',
                value: preferences.fontSize,
                min: 14,
                max: 30,
                displayValue: preferences.fontSize.toStringAsFixed(1),
                onChanged: (value) =>
                    onPreferencesChanged(preferences.copyWith(fontSize: value)),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-line-height-slider'),
                label: '行高',
                value: preferences.lineHeight,
                min: 1.2,
                max: 2.4,
                displayValue: preferences.lineHeight.toStringAsFixed(1),
                onChanged: (value) =>
                    onPreferencesChanged(preferences.copyWith(lineHeight: value)),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-paragraph-spacing-slider'),
                label: '段距',
                value: preferences.paragraphSpacing,
                min: 0,
                max: 28,
                displayValue: preferences.paragraphSpacing.toStringAsFixed(0),
                onChanged: (value) => onPreferencesChanged(
                  preferences.copyWith(paragraphSpacing: value),
                ),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-page-padding-slider'),
                label: '边距',
                value: preferences.pagePadding,
                min: 8,
                max: 40,
                displayValue: preferences.pagePadding.toStringAsFixed(0),
                onChanged: (value) =>
                    onPreferencesChanged(preferences.copyWith(pagePadding: value)),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-first-line-indent-slider'),
                label: '首行缩进',
                value: preferences.firstLineIndent,
                min: 0,
                max: 48,
                displayValue: preferences.firstLineIndent.toStringAsFixed(0),
                onChanged: (value) => onPreferencesChanged(
                  preferences.copyWith(firstLineIndent: value),
                ),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-content-width-slider'),
                label: '正文宽度',
                value: preferences.contentMaxWidth,
                min: 320,
                max: 900,
                displayValue: preferences.contentMaxWidth.toStringAsFixed(0),
                onChanged: (value) => onPreferencesChanged(
                  preferences.copyWith(contentMaxWidth: value),
                ),
              ),
              ReaderSegmentControl<int>(
                key: const Key('novel-reader-font-weight-control'),
                label: '字重',
                value: _supportedFontWeight(preferences.fontWeight),
                values: const <int>[400, 500, 700],
                labelBuilder: _fontWeightLabel,
                onChanged: (value) =>
                    onPreferencesChanged(preferences.copyWith(fontWeight: value)),
              ),
              ReaderSegmentControl<NovelReaderTextAlignMode>(
                key: const Key('novel-reader-text-align-control'),
                label: '对齐',
                value: preferences.textAlign,
                values: NovelReaderTextAlignMode.values,
                labelBuilder: _textAlignLabel,
                onChanged: (value) =>
                    onPreferencesChanged(preferences.copyWith(textAlign: value)),
              ),
            ],
          ),
          _SettingsSection(
            title: '主题',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ThemeChip(
                      key: const Key('novel-theme-light'),
                      label: '浅色',
                      selected: preferences.themePreset == NovelReaderThemePreset.light,
                      onSelected: () => onPreferencesChanged(
                        preferences.copyWith(themePreset: NovelReaderThemePreset.light),
                      ),
                    ),
                    _ThemeChip(
                      key: const Key('novel-theme-sepia'),
                      label: '护眼',
                      selected: preferences.themePreset == NovelReaderThemePreset.sepia,
                      onSelected: () => onPreferencesChanged(
                        preferences.copyWith(themePreset: NovelReaderThemePreset.sepia),
                      ),
                    ),
                    _ThemeChip(
                      key: const Key('novel-theme-dark'),
                      label: '深色',
                      selected: preferences.themePreset == NovelReaderThemePreset.dark,
                      onSelected: () => onPreferencesChanged(
                        preferences.copyWith(themePreset: NovelReaderThemePreset.dark),
                      ),
                    ),
                    _ThemeChip(
                      key: const Key('novel-theme-follow-system'),
                      label: '跟随系统',
                      selected:
                          preferences.themePreset == NovelReaderThemePreset.followSystem,
                      onSelected: () => onPreferencesChanged(
                        preferences.copyWith(
                          themePreset: NovelReaderThemePreset.followSystem,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: '阅读',
            children: [
              ReaderSegmentControl<NovelReaderFlowMode>(
                key: const Key('novel-reader-flow-mode-control'),
                label: '模式',
                value: preferences.flowMode,
                values: NovelReaderFlowMode.values,
                labelBuilder: _flowModeLabel,
                onChanged: (value) =>
                    onPreferencesChanged(preferences.copyWith(flowMode: value)),
              ),
              SwitchListTile(
                key: const Key('novel-reader-show-progress-switch'),
                title: const Text('显示进度控件'),
                value: preferences.showProgressIndicator,
                onChanged: (value) => onPreferencesChanged(
                  preferences.copyWith(showProgressIndicator: value),
                ),
              ),
              SwitchListTile(
                key: const Key('novel-reader-show-chapter-title-switch'),
                title: const Text('正文显示章节标题'),
                value: preferences.showChapterTitle,
                onChanged: (value) => onPreferencesChanged(
                  preferences.copyWith(showChapterTitle: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fontWeightLabel(int value) {
    switch (value) {
      case 500:
        return '中等';
      case 700:
        return '加粗';
      case 400:
      default:
        return '常规';
    }
  }

  int _supportedFontWeight(int value) {
    switch (value) {
      case 500:
      case 700:
        return value;
      case 400:
      default:
        return 400;
    }
  }

  String _textAlignLabel(NovelReaderTextAlignMode value) {
    switch (value) {
      case NovelReaderTextAlignMode.justify:
        return '两端';
      case NovelReaderTextAlignMode.center:
        return '居中';
      case NovelReaderTextAlignMode.start:
        return '默认';
    }
  }

  String _flowModeLabel(NovelReaderFlowMode value) {
    switch (value) {
      case NovelReaderFlowMode.pagedLtr:
        return '分页';
      case NovelReaderFlowMode.pagedRtl:
        return '右翻';
      case NovelReaderFlowMode.vertical:
        return '滚动';
    }
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsSlider extends StatelessWidget {
  const _SettingsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              displayValue,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
