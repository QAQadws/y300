import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_editor_mode.dart';

/// 源码 / 预览模式切换。
///
/// `widgetKey` 让回复页与（后续阶段的）发帖页保留各自稳定的 widget key，
/// 同时复用同一段实现。
class ComposerModeSwitch extends StatelessWidget {
  const ComposerModeSwitch({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.enabled = true,
    this.widgetKey,
  });

  final ComposerEditorMode mode;
  final ValueChanged<ComposerEditorMode> onModeChanged;
  final bool enabled;
  final Key? widgetKey;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<ComposerEditorMode>(
        key: widgetKey,
        segments: const [
          ButtonSegment<ComposerEditorMode>(
            value: ComposerEditorMode.source,
            label: Text('源码'),
            icon: Icon(Icons.edit_note),
          ),
          ButtonSegment<ComposerEditorMode>(
            value: ComposerEditorMode.preview,
            label: Text('预览'),
            icon: Icon(Icons.visibility),
          ),
        ],
        selected: {mode},
        onSelectionChanged: enabled
            ? (selection) {
                onModeChanged(selection.single);
              }
            : null,
      ),
    );
  }
}
