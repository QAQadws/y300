import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_input.dart';
import 'package:y300/features/profile/presentation/blog/blog_body_text_codec.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('representation switches preserve exact HTML without editing', (
    tester,
  ) async {
    const source = 'a &amp; b<br />\n第二行';
    final changed = <String>[];
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: BlogBodyInput(
            html: source,
            enabled: true,
            readOnly: false,
            onChanged: changed.add,
          ),
        ),
      ),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a & b\n第二行',
    );
    await tester.tap(find.byKey(const Key('blog-body-html-mode')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      source,
    );
    await tester.tap(find.byKey(const Key('blog-body-text-mode')));
    await tester.pump();
    expect(changed, isEmpty);
  });

  testWidgets(
    'rich source cannot be flattened and external replacement is visible',
    (tester) async {
      final source = ValueNotifier('<p class="keep"><b>原文</b></p>');
      addTearDown(source.dispose);
      final changed = <String>[];
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: source,
              builder: (_, value, _) => BlogBodyInput(
                html: value,
                enabled: true,
                readOnly: false,
                onChanged: changed.add,
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('blog-body-text-mode')))
            .onSelected,
        isNull,
      );
      source.value = '<p>Server version</p>';
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        source.value,
      );
      expect(changed, isEmpty);
    },
  );

  testWidgets('plain typing escapes markup and retains whitespace', (
    tester,
  ) async {
    var saved = '';
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: BlogBodyInput(
            html: '',
            enabled: true,
            readOnly: false,
            onChanged: (value) => saved = value,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      '  <b>literal</b> &\n\nsecond',
    );
    expect(BlogBodyTextCodec.decode(saved), '  <b>literal</b> &\n\nsecond');
    expect(saved, contains('&lt;b&gt;'));
  });
}
