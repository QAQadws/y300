import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelReaderDisplaySettingsSheet extends StatefulWidget {
  const NovelReaderDisplaySettingsSheet({
    super.key,
    required this.initialPreferences,
    required this.onPreviewRequested,
  });

  final NovelReaderPreferences initialPreferences;
  final ValueChanged<NovelReaderPreferences> onPreviewRequested;

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
                value: _draft.fontSize,
                min: 14,
                max: 30,
                displayValue: _draft.fontSize.toStringAsFixed(1),
                onChanged: (value) => _updateDraft(
                  _draft.copyWith(fontSize: value),
                ),
                onChangeEnd: (_) => _previewDraft(),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-line-height-slider'),
                label: '行高',
                value: _draft.lineHeight,
                min: 1.2,
                max: 2.4,
                displayValue: _draft.lineHeight.toStringAsFixed(1),
                onChanged: (value) => _updateDraft(
                  _draft.copyWith(lineHeight: value),
                ),
                onChangeEnd: (_) => _previewDraft(),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-paragraph-spacing-slider'),
                label: '段距',
                value: _draft.paragraphSpacing,
                min: 0,
                max: 28,
                displayValue: _draft.paragraphSpacing.toStringAsFixed(0),
                onChanged: (value) => _updateDraft(
                  _draft.copyWith(paragraphSpacing: value),
                ),
                onChangeEnd: (_) => _previewDraft(),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-page-padding-slider'),
                label: '边距',
                value: _draft.pagePadding,
                min: 8,
                max: 40,
                displayValue: _draft.pagePadding.toStringAsFixed(0),
                onChanged: (value) => _updateDraft(
                  _draft.copyWith(pagePadding: value),
                ),
                onChangeEnd: (_) => _previewDraft(),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-first-line-indent-slider'),
                label: '首行缩进',
                value: _draft.firstLineIndent,
                min: 0,
                max: 48,
                displayValue: _draft.firstLineIndent.toStringAsFixed(0),
                onChanged: (value) => _updateDraft(
                  _draft.copyWith(firstLineIndent: value),
                ),
                onChangeEnd: (_) => _previewDraft(),
              ),
              _SettingsSlider(
                key: const Key('novel-reader-content-width-slider'),
                label: '正文宽度',
                value: _draft.contentMaxWidth,
                min: 320,
                max: 900,
                displayValue: _draft.contentMaxWidth.toStringAsFixed(0),
                onChanged: (value) => _updateDraft(
                  _draft.copyWith(contentMaxWidth: value),
                ),
                onChangeEnd: (_) => _previewDraft(),
              ),
              ReaderSegmentControl<int>(
                key: const Key('novel-reader-font-weight-control'),
                label: '字重',
                value: _supportedFontWeight(_draft.fontWeight),
                values: const <int>[400, 500, 700],
                labelBuilder: _fontWeightLabel,
                onChanged: (value) => _applyImmediatePreview(
                  _draft.copyWith(fontWeight: value),
                ),
              ),
              ReaderSegmentControl<NovelReaderTextAlignMode>(
                key: const Key('novel-reader-text-align-control'),
                label: '对齐',
                value: _draft.textAlign,
                values: NovelReaderTextAlignMode.values,
                labelBuilder: _textAlignLabel,
                onChanged: (value) => _applyImmediatePreview(
                  _draft.copyWith(textAlign: value),
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
                      selected: _draft.themePreset == NovelReaderThemePreset.light,
                      onSelected: () => _applyImmediatePreview(
                        _draft.copyWith(
                          themePreset: NovelReaderThemePreset.light,
                        ),
                      ),
                    ),
                    _ThemeChip(
                      key: const Key('novel-theme-sepia'),
                      label: '护眼',
                      selected: _draft.themePreset == NovelReaderThemePreset.sepia,
                      onSelected: () => _applyImmediatePreview(
                        _draft.copyWith(
                          themePreset: NovelReaderThemePreset.sepia,
                        ),
                      ),
                    ),
                    _ThemeChip(
                      key: const Key('novel-theme-dark'),
                      label: '深色',
                      selected: _draft.themePreset == NovelReaderThemePreset.dark,
                      onSelected: () => _applyImmediatePreview(
                        _draft.copyWith(
                          themePreset: NovelReaderThemePreset.dark,
                        ),
                      ),
                    ),
                    _ThemeChip(
                      key: const Key('novel-theme-follow-system'),
                      label: '跟随系统',
                      selected: _draft.themePreset ==
                          NovelReaderThemePreset.followSystem,
                      onSelected: () => _applyImmediatePreview(
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
                label: '模式',
                value: _draft.flowMode,
                values: NovelReaderFlowMode.values,
                labelBuilder: _flowModeLabel,
                onChanged: (value) => _applyImmediatePreview(
                  _draft.copyWith(flowMode: value),
                ),
              ),
              SwitchListTile(
                key: const Key('novel-reader-show-progress-switch'),
                title: const Text('显示进度控件'),
                value: _draft.showProgressIndicator,
                onChanged: (value) => _applyImmediatePreview(
                  _draft.copyWith(showProgressIndicator: value),
                ),
              ),
              SwitchListTile(
                key: const Key('novel-reader-show-chapter-title-switch'),
                title: const Text('正文显示章节标题'),
                value: _draft.showChapterTitle,
                onChanged: (value) => _applyImmediatePreview(
                  _draft.copyWith(showChapterTitle: value),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('novel-reader-display-settings-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('novel-reader-display-settings-save'),
                    onPressed: _draft == widget.initialPreferences
                        ? null
                        : () => Navigator.of(context).pop(_draft),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateDraft(NovelReaderPreferences next) {
    setState(() {
      _draft = next;
    });
  }

  void _applyImmediatePreview(NovelReaderPreferences next) {
    _updateDraft(next);
    widget.onPreviewRequested(next);
  }

  void _previewDraft() {
    widget.onPreviewRequested(_draft);
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
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

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
              onChangeEnd: onChangeEnd,
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
