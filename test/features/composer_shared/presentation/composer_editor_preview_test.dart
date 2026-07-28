import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_editor_preview.dart';

void main() {
  testWidgets('ComposerEditorPreview adds BBCode actions for selected text', (
    tester,
  ) async {
    final controller = TextEditingController(text: '前选中后');
    addTearDown(controller.dispose);
    String changed = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onChanged: (value) => changed = value,
      ),
    );
    await tester.tap(find.byKey(const Key('test-composer-input')));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();

    expect(find.text('加粗'), findsOneWidget);
    expect(find.text('字体色'), findsOneWidget);
    expect(find.text('背景色'), findsOneWidget);
    expect(find.text('引用'), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('居中'), findsNothing);
    expect(find.text('代码'), findsNothing);
    expect(find.text('Share'), findsNothing);

    await tester.tap(find.text('加粗'));
    await tester.pumpAndSettle();

    expect(controller.text, '前[b]选中[/b]后');
    expect(changed, '前[b]选中[/b]后');
  });

  testWidgets('ComposerEditorPreview wraps selection with picked color', (
    tester,
  ) async {
    final controller = TextEditingController(text: '前选中后');
    addTearDown(controller.dispose);
    String changed = '';

    await tester.pumpWidget(
      _buildEditor(
        controller: controller,
        onChanged: (value) => changed = value,
      ),
    );
    await tester.tap(find.byKey(const Key('test-composer-input')));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('字体色'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-selection-color-sheet')),
      findsOneWidget,
    );
    final picker = tester.widget<ColorPicker>(
      find.byKey(const Key('composer-selection-color-picker')),
    );
    picker.onColorChanged(const Color(0xff112233));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('composer-selection-color-use-button')),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '前[color=#112233]选中[/color]后');
    expect(changed, '前[color=#112233]选中[/color]后');
  });

  testWidgets('ComposerEditorPreview wraps selection with picked backcolor', (
    tester,
  ) async {
    final controller = TextEditingController(text: '前选中后');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_buildEditor(controller: controller));
    await tester.tap(find.byKey(const Key('test-composer-input')));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('背景色'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-selection-backcolor-sheet')),
      findsOneWidget,
    );
    final picker = tester.widget<ColorPicker>(
      find.byKey(const Key('composer-selection-backcolor-picker')),
    );
    picker.onColorChanged(const Color(0xffaabbcc));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('composer-selection-backcolor-use-button')),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '前[backcolor=#aabbcc]选中[/backcolor]后');
  });

  testWidgets('ComposerEditorPreview hides BBCode actions without selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: '正文');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_buildEditor(controller: controller));
    await tester.tap(find.byKey(const Key('test-composer-input')));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 1);

    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();

    expect(find.text('加粗'), findsNothing);
    expect(find.text('颜色'), findsNothing);
    expect(find.text('背景'), findsNothing);
  });
}

Widget _buildEditor({
  required TextEditingController controller,
  ValueChanged<String>? onChanged,
}) {
  return LocalizedTestApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ComposerEditorPreview(
        inputKey: const Key('test-composer-input'),
        controller: controller,
        enabled: true,
        hintText: '正文',
        onChanged: onChanged ?? (_) {},
        renderer: const FlutterBbCodeForumRenderer(),
      ),
    ),
  );
}
