import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:y300/features/novel/presentation/services/novel_reader_scroll_markup.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  test('project produces exact HTML and ordered immutable safe fragments', () {
    final first = '甲' * 1600;
    final second = '乙' * 1600;
    final last = '丙' * 9000;
    final input = '$first<BR/>$second<br>$last';
    String block(String text) =>
        '<y300-novel-text-chunk style="display:block;margin:0">'
        '$text</y300-novel-text-chunk>';
    final projection = NovelReaderScrollMarkup.project(input);

    expect(projection.html, '${block(first)}${block(second)}${block(last)}');
    expect(projection.fragments, [block(first), block(second), block(last)]);
    expect(projection.html, NovelReaderScrollMarkup.prepare(input));
    expect(
      projection.fragments,
      NovelReaderScrollMarkup.fragments(projection.html),
    );
    expect(() => projection.fragments!.clear(), throwsUnsupportedError);
  });

  test('small and no-change projections preserve original input bytes', () {
    final inputs = [
      '',
      "<p data-key='x'>正文&nbsp;</p>",
      '正文<br>正文',
      '<div style="color:red">${'正文' * 7000}</div>',
      '<font color="red">${'正文<br>' * 3000}</font>',
      '${'甲' * 6000}<br data-kind="authored">${'乙' * 6000}',
    ];
    for (final input in inputs) {
      final projection = NovelReaderScrollMarkup.project(input);
      expect(projection.html, same(input));
      expect(projection.fragments, isNull);
      expect(NovelReaderScrollMarkup.prepare(input), same(input));
    }
  });

  test('original reserved markers retain short and long compatibility behavior', () {
    for (final prefix in ['before', '正文' * 6500]) {
      final input =
          '$prefix<y300-novel-text-chunk style=\'display:block;margin:0\'>first</y300-novel-text-chunk>'
          '<b>between</b><y300-novel-text-chunk>second</y300-novel-text-chunk><i>end</i>';
      final projection = NovelReaderScrollMarkup.project(input);
      expect(projection.html, same(input));
      expect(projection.fragments, [
        '$prefix<y300-novel-text-chunk style="display:block;margin:0">first</y300-novel-text-chunk>',
        '<b>between</b><y300-novel-text-chunk>second</y300-novel-text-chunk><i>end</i>',
      ]);
    }
  });

  test(
    'marker spelling guard and nested or single markers remain unchanged',
    () {
      final inputs = [
        '<Y300-NOVEL-TEXT-CHUNK>first</Y300-NOVEL-TEXT-CHUNK>'
            '<Y300-NOVEL-TEXT-CHUNK>second</Y300-NOVEL-TEXT-CHUNK>',
        '<div><y300-novel-text-chunk>first</y300-novel-text-chunk>'
            '<y300-novel-text-chunk>second</y300-novel-text-chunk></div>',
        '${'正文' * 6500}<y300-novel-text-chunk>only</y300-novel-text-chunk>',
        '<!-- <y300-novel-text-chunk> -->${'正文' * 6500}',
      ];
      for (final input in inputs) {
        final projection = NovelReaderScrollMarkup.project(input);
        expect(projection.html, same(input));
        expect(projection.fragments, isNull);
        expect(NovelReaderScrollMarkup.fragments(input), isNull);
      }
    },
  );

  for (final separator in ['<BR>', '<bR/>', '</Br>']) {
    test(
      'case variants and end BR tags still acquire boundaries: $separator',
      () {
        final lines = [
          for (var index = 0; index < 7; index++) '文$index${'字' * 1900}',
        ];
        final input = lines.join(separator);
        final projection = NovelReaderScrollMarkup.project(input);
        final expected = [
          for (final line in lines)
            '<y300-novel-text-chunk style="display:block;margin:0">'
                '$line</y300-novel-text-chunk>',
        ];
        expect(projection.html, expected.join());
        expect(projection.fragments, expected);
      },
    );
  }

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
