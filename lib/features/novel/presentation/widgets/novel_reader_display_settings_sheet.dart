import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelReaderDisplaySettingsSheet extends StatefulWidget {
  const NovelReaderDisplaySettingsSheet({
    super.key,
    required this.initialPreferences,
    required this.onPreferencesChanged,
  });

  final NovelReaderPreferences initialPreferences;
  final ValueChanged<NovelReaderPreferences> onPreferencesChanged;

  @override
  State<NovelReaderDisplaySettingsSheet> createState() =>
      _NovelReaderDisplaySettingsSheetState();
}

class _NovelReaderDisplaySettingsSheetState
    extends State<NovelReaderDisplaySettingsSheet> {
  late NovelReaderPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialPreferences;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
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
                    value: _draft.fontSize,
                    min: 14,
                    max: 30,
                    displayValue: _draft.fontSize.toStringAsFixed(1),
                    onChanged: (value) => _applyPreferences(
                      _draft.copyWith(fontSize: _snap(value, 0.5)),
                    ),
                  ),
                  _SettingsSlider(
                    key: const Key('novel-reader-line-height-slider'),
                    label: '间隔',
                    value: _draft.lineHeight,
                    min: 1.2,
                    max: 2.4,
                    displayValue: _draft.lineHeight.toStringAsFixed(1),
                    onChanged: (value) => _applyPreferences(
                      _draft.copyWith(lineHeight: _snap(value, 0.05)),
                    ),
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
                          selected:
                              _draft.themePreset ==
                              NovelReaderThemePreset.light,
                          onSelected: () => _applyPreferences(
                            _draft.copyWith(
                              themePreset: NovelReaderThemePreset.light,
                            ),
                          ),
                        ),
                        _ThemeChip(
                          key: const Key('novel-theme-sepia'),
                          label: '护眼',
                          selected:
                              _draft.themePreset ==
                              NovelReaderThemePreset.sepia,
                          onSelected: () => _applyPreferences(
                            _draft.copyWith(
                              themePreset: NovelReaderThemePreset.sepia,
                            ),
                          ),
                        ),
                        _ThemeChip(
                          key: const Key('novel-theme-dark'),
                          label: '深色',
                          selected:
                              _draft.themePreset == NovelReaderThemePreset.dark,
                          onSelected: () => _applyPreferences(
                            _draft.copyWith(
                              themePreset: NovelReaderThemePreset.dark,
                            ),
                          ),
                        ),
                        _ThemeChip(
                          key: const Key('novel-theme-follow-system'),
                          label: '跟随系统',
                          selected:
                              _draft.themePreset ==
                              NovelReaderThemePreset.followSystem,
                          onSelected: () => _applyPreferences(
                            _draft.copyWith(
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
                    label: '阅读模式',
                    value: _draft.flowMode,
                    values: NovelReaderFlowMode.values,
                    labelBuilder: _flowModeLabel,
                    onChanged: (value) =>
                        _applyPreferences(_draft.copyWith(flowMode: value)),
                  ),
                  ReaderSegmentControl<NovelReaderConversionMode>(
                    key: const Key('novel-reader-conversion-mode-control'),
                    label: '简繁',
                    value: _draft.conversionMode,
                    values: NovelReaderConversionMode.values,
                    labelBuilder: _conversionModeLabel,
                    onChanged: (value) => _applyPreferences(
                      _draft.copyWith(conversionMode: value),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('novel-reader-safe-area-switch'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: const Text('安全显示正文'),
                    value: _draft.safeAreaEnabled,
                    onChanged: (value) => _applyPreferences(
                      _draft.copyWith(safeAreaEnabled: value),
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

  void _applyPreferences(NovelReaderPreferences next) {
    if (next == _draft) {
      return;
    }
    setState(() {
      _draft = next;
    });
    widget.onPreferencesChanged(next);
  }

  double _snap(double value, double step) {
    return (value / step).roundToDouble() * step;
  }

  String _conversionModeLabel(NovelReaderConversionMode value) {
    switch (value) {
      case NovelReaderConversionMode.none:
        return '原文';
      case NovelReaderConversionMode.toSimplified:
        return '简体';
      case NovelReaderConversionMode.toTraditional:
        return '繁体';
    }
  }

  String _flowModeLabel(NovelReaderFlowMode value) {
    switch (value) {
      case NovelReaderFlowMode.vertical:
        return '滚动';
      case NovelReaderFlowMode.pagedLtr:
        return '分页 LTR';
      case NovelReaderFlowMode.pagedRtl:
        return '分页 RTL';
    }
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

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
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
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
