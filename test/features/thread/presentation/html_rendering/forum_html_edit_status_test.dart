import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

const _statusKey = Key('forum-html-discuz-edit-status');
const _notice = '本帖最后由 fixture-user-with-a-long-name 于 2026-1-1 12:34 编辑';

void main() {
  for (final width in [240.0, 360.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits the entire notice at width=$width scale=$scale', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _host(width: width, fontScale: scale, systemScale: scale),
          );
          await tester.pumpAndSettle();

          final paragraph = _paragraph(tester);
          final fitted = _fitted(tester);
          final painted = MatrixUtils.transformRect(
            paragraph.getTransformTo(fitted),
            Offset.zero & paragraph.size,
          );
          expect(paragraph.text.toPlainText(), _notice);
          expect(paragraph.maxLines, 1);
          expect(paragraph.softWrap, isFalse);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(painted.left, greaterThanOrEqualTo(-0.01));
          expect(painted.right, lessThanOrEqualTo(width + 0.01));
          expect(painted.height, closeTo(fitted.size.height, 0.01));
          expect(painted.height, lessThanOrEqualTo(paragraph.size.height));
          expect(find.bySemanticsLabel(_notice), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(tester.binding.hasScheduledFrame, isFalse);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('settings update the base size; fitting never enlarges text', (
    tester,
  ) async {
    const shortNotice = '本帖最后编辑';
    await tester.pumpWidget(_host(text: shortNotice, fontScale: 1));
    await tester.pumpAndSettle();
    final smallSize = _paragraph(tester).size;
    expect(
      tester.widget<Text>(find.byKey(_statusKey)).style?.fontSize,
      14 * 0.88,
    );
    expect(_fitted(tester).size.height, smallSize.height);

    await tester.pumpWidget(_host(text: shortNotice, fontScale: 1.8));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(_statusKey)).style?.fontSize,
      closeTo(14 * 1.8 * 0.88, 0.001),
    );
    expect(_paragraph(tester).size.height, greaterThan(smallSize.height));
    expect(_fitted(tester).size.height, _paragraph(tester).size.height);
  });

  testWidgets('width changes refit the same line without a rebuild loop', (
    tester,
  ) async {
    await tester.pumpWidget(_host(width: 240));
    await tester.pumpAndSettle();
    final narrowHeight = _fitted(tester).size.height;
    final naturalSize = _paragraph(tester).size;

    await tester.pumpWidget(_host(width: 700));
    await tester.pumpAndSettle();
    expect(_fitted(tester).size.height, greaterThan(narrowHeight));
    expect(_paragraph(tester).size, naturalSize);
    expect(_paragraph(tester).text.toPlainText(), _notice);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('normalizes hard breaks without truncating traditional text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        text: ' 本帖最後由\n fixture-user\u2028於\t2026-1-1\u2029編輯 ',
        width: 240,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _paragraph(tester).text.toPlainText(),
      '本帖最後由 fixture-user 於 2026-1-1 編輯',
    );
    expect(_paragraph(tester).didExceedMaxLines, isFalse);
  });

  testWidgets('ordinary prose and italic text are not treated as metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(html: '<i>$_notice</i><p>普通正文仍允许换行。</p>', width: 240),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_statusKey), findsNothing);
    expect(find.byType(FittedBox), findsNothing);
    expect(find.textContaining(_notice, findRichText: true), findsOneWidget);
  });
}

RenderParagraph _paragraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(_statusKey),
        matching: find.byType(RichText),
      ),
    );

RenderFittedBox _fitted(WidgetTester tester) =>
    tester.renderObject<RenderFittedBox>(
      find.ancestor(
        of: find.byKey(_statusKey),
        matching: find.byType(FittedBox),
      ),
    );

Widget _host({
  String text = _notice,
  String? html,
  double width = 600,
  double fontScale = 1,
  double systemScale = 1,
}) {
  return LocalizedTestApp(
    theme: ThemeData(
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(systemScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ForumHtmlWidgetPostRenderer(
              html: html ?? '<i class="pstatus">$text</i><br><br><p>正文</p>',
              theme: forumHtmlTestTheme,
              buildAsync: false,
              preferences: ForumHtmlReaderPreferences.defaults().copyWith(
                typography: RichTextTypography(
                  fontScale: fontScale,
                  lineHeightScale: 1.5,
                  paragraphSpacing: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
