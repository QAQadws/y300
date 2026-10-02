import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_input.dart';
import 'package:y300/features/profile/presentation/blog/blog_quill_html_codec.dart';
import 'package:y300/features/profile/presentation/blog/blog_rich_text_controller.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('keyboard replacement rejects foreign attachment embeds', (
    tester,
  ) async {
    final changed = <String>[];
    final controller = BlogRichTextController(onChanged: changed.add)
      ..load('正文');
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    controller.quill.replaceText(
      0,
      0,
      const Embeddable('attach', '123'),
      const TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    expect(controller.quill.document.toPlainText(), '正文\n');
    expect(changed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one visual editor shows decoded text without rewriting the source',
    (tester) async {
      const source = 'a &amp; b<br />\n第二行';
      final changed = <String>[];
      final controller = BlogRichTextController(onChanged: changed.add)
        ..load(source);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('blog-body-mode-menu')), findsNothing);
      expect(controller.quill.document.toPlainText(), 'a & b\n第二行\n');
      controller.quill.updateSelection(
        const TextSelection.collapsed(offset: 2),
        ChangeSource.local,
      );
      await tester.pump();
      expect(changed, isEmpty);
    },
  );

  testWidgets(
    'rich source is styled and external replacement does not report an edit',
    (tester) async {
      final changed = <String>[];
      final controller = BlogRichTextController(onChanged: changed.add)
        ..load('<p><b>原文</b></p>');
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      expect(controller.quill.document.toPlainText(), '原文\n');
      expect(
        controller.quill.document
            .toDelta()
            .first
            .attributes?[Attribute.bold.key],
        isTrue,
      );
      controller.load('<p>Server version</p>');
      await tester.pump();
      expect(controller.quill.document.toPlainText(), 'Server version\n');
      expect(changed, isEmpty);
    },
  );

  testWidgets(
    'visual typing escapes literal markup and retains spaces and blank lines',
    (tester) async {
      var saved = '';
      final controller = BlogRichTextController(
        onChanged: (value) => saved = value,
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      const text = '  <b>literal</b> &\n\nsecond';
      controller.quill.replaceText(
        0,
        0,
        text,
        const TextSelection.collapsed(offset: text.length),
      );
      await tester.pump();
      expect(
        const BlogQuillHtmlCodec().decodeDocument(saved).toPlainText(),
        '$text\n',
      );
      expect(saved, contains('&lt;b&gt;'));
    },
  );

  for (final disabled in [false, true]) {
    testWidgets(
      '${disabled ? 'disabled' : 'readonly'} body retains copyable content',
      (tester) async {
        final controller = BlogRichTextController(onChanged: (_) {})
          ..load('<p>Keep reading</p>');
        addTearDown(controller.dispose);
        await _pump(
          tester,
          controller,
          enabled: !disabled,
          readOnly: !disabled,
        );
        final input = tester.widget<QuillEditor>(
          find.byKey(const Key('blog-editor-body')),
        );
        expect(input.controller.readOnly, isTrue);
        expect(input.controller.document.toPlainText(), 'Keep reading\n');
        expect(input.config.showCursor, isFalse);
        expect(input.config.enableInteractiveSelection, isTrue);
      },
    );
  }

  testWidgets('normal and double text sizes fit a narrow writing area', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = BlogRichTextController(onChanged: (_) {})
      ..load('<p>正文与换行</p><p>第二段文字</p>');
    addTearDown(controller.dispose);
    for (final scale in [1.0, 2.0]) {
      await _pump(tester, controller, scale: scale);
      expect(tester.takeException(), isNull);
      final bounds = tester.getRect(find.byKey(const Key('blog-editor-body')));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(300));
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  BlogRichTextController controller, {
  bool enabled = true,
  bool readOnly = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    LocalizedTestApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlogBodyInput(
            controller: controller,
            enabled: enabled,
            readOnly: readOnly,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
