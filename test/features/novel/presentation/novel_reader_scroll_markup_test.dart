import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:y300/features/novel/presentation/services/novel_reader_scroll_markup.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  test('small and styled documents remain unchanged', () {
    expect(NovelReaderScrollMarkup.prepare('正文<br>正文'), '正文<br>正文');
    final styled =
        '<font color="#ff0000">${List.filled(3000, '文本<br>').join()}</font>';
    expect(NovelReaderScrollMarkup.prepare(styled), styled);
  });

  test('long plain v1 lines keep every character and protected sibling', () {
    final text = List.generate(
      300,
      (i) => 'fixture-$i ${List.filled(30, '字').join()}😀<br><br>',
    ).join();
    final html = '$text<div class="showcollapse_box"><b>折叠</b></div>';
    final output = parser.parseFragment(NovelReaderScrollMarkup.prepare(html));
    expect(output.text, parser.parseFragment(html).text);
    final chunks = output.querySelectorAll('y300-novel-text-chunk');
    expect(chunks.length, greaterThan(2));
    expect(
      chunks.map((node) => node.text.length),
      everyElement(lessThan(1800)),
    );
    expect(
      output.querySelector('.showcollapse_box')!.outerHtml,
      '<div class="showcollapse_box"><b>折叠</b></div>',
    );
  });

  for (final separator in ['<br>', '<br><br>', '<br>\r\n<br>\r\n']) {
    testWidgets('chunking preserves line and blank spacing: $separator', (
      tester,
    ) async {
      final html = List.generate(
        180,
        (i) => 'fixture-$i ${List.filled(70, '文').join()}',
      ).join(separator);
      final chunked = NovelReaderScrollMarkup.prepare(html);
      expect(chunked, isNot(html));
      Future<double> height(String content, {bool separate = false}) async {
        await tester.pumpWidget(
          LocalizedTestApp(
            home: SingleChildScrollView(
              child: SizedBox(
                key: const Key('fixture-measured-document'),
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final html
                        in separate
                            ? NovelReaderScrollMarkup.fragments(content)!
                            : [content])
                      ForumHtmlWidgetPostRenderer(
                        key: ValueKey(html),
                        html: html,
                        theme: _theme,
                        buildAsync: false,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .getSize(find.byKey(const Key('fixture-measured-document')))
            .height;
      }

      final originalHeight = await height(html);
      final chunkedHeight = await height(chunked);
      final separateHeight = await height(chunked, separate: true);
      expect(separateHeight, closeTo(chunkedHeight, 0.01));
      // Each text box rounds its height independently; no extra blank lines.
      final chunks = parser
          .parseFragment(chunked)
          .querySelectorAll('y300-novel-text-chunk')
          .length;
      expect(
        (originalHeight - chunkedHeight).abs(),
        lessThanOrEqualTo(chunks.toDouble()),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Colors.white,
  foreground: Colors.black,
  link: Colors.blue,
  quoteSurface: Colors.white,
  quoteForeground: Colors.black,
  codeSurface: Colors.white,
  codeForeground: Colors.black,
);
