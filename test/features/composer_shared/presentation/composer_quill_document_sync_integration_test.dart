import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_bbcode_codec.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_quill_prototype_editor.dart';

import '../../../test_support/localized_test_app.dart';

const _codec = ComposerQuillBbCodeCodec();

void main() {
  testWidgets(
    'surface keeps the current callback without resetting document or caret',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      final first = <String>[];
      final current = <String>[];
      await tester.pumpWidget(_editor(controller, onChanged: first.add));
      final document = controller.document;
      controller.replaceText(
        0,
        0,
        '正文',
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pumpWidget(_editor(controller, onChanged: current.add));
      controller.replaceText(
        1,
        0,
        '新',
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pumpAndSettle();
      expect(first, ['正文']);
      expect(current, ['正新文']);
      expect(controller.document, same(document));
      expect(controller.selection.baseOffset, 2);
    },
  );

  testWidgets(
    'external insertion projects its caret and parent echo preserves it',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        _editor(controller, source: '', onChanged: changes.add),
      );
      const source = '😀[attach]42[/attach]后';
      final offset = source.indexOf('后');
      final mutation = ComposerTextMutation(
        previousSource: '😀后',
        nextSource: source,
        replacedSelection: const ComposerSelection(start: 2, end: 2),
        resultSelection: ComposerSelection(start: offset, end: offset),
        revision: 2,
      );
      await tester.pumpWidget(
        _editor(
          controller,
          source: source,
          revision: 2,
          mutation: mutation,
          onChanged: changes.add,
        ),
      );
      expect(controller.selection.baseOffset, 3);
      final document = controller.document;
      await tester.pumpWidget(
        _editor(
          controller,
          source: source,
          revision: 3,
          onChanged: changes.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.document, same(document));
      expect(controller.selection.baseOffset, 3);
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    'unmount retires pending promotion and leaves an external controller usable',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(_editor(controller, onChanged: changes.add));
      const token = '[attach]42[/attach]';
      controller.replaceText(
        0,
        0,
        token,
        const TextSelection.collapsed(offset: token.length),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.document.toPlainText(), '$token\n');
      controller.replaceText(
        0,
        0,
        '正文',
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      expect(changes, [token]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'caller document replacement invalidates an already open collapse editor',
    (tester) async {
      const source = '[collapse=0,原始标题]\n正文[/collapse]';
      final controller = QuillController(
        document: _codec.decodeDocument(source),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_editor(controller));
      await tester.tap(
        find.byKey(const Key('composer-quill-collapse-edit-collapse-0')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sync-quill-collapse-editor-title-field')),
        '旧编辑结果',
      );
      controller.document = _codec.decodeDocument(source);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('sync-quill-collapse-editor-save-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sync-quill-collapse-editor-page')),
        findsOneWidget,
      );
      expect(_codec.encodeDocument(controller.document), source);
    },
  );
}

Widget _editor(
  QuillController controller, {
  String? source,
  int revision = 0,
  ComposerTextMutation? mutation,
  ValueChanged<String>? onChanged,
}) => LocalizedTestApp(
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 600,
      child: ComposerQuillEditorSurface(
        controller: controller,
        bbCode: source,
        messageRevision: revision,
        lastMessageMutation: mutation,
        onBbCodeChanged: onChanged,
        keyPrefix: 'sync-quill',
      ),
    ),
  ),
);
