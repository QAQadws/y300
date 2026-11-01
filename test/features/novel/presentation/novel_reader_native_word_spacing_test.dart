import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester,
  NovelReaderWordSpacing? request, {
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
}) async {
  late NovelReaderNativeRenderEnvironment result;
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: Theme(
          data: ThemeData.light().copyWith(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(
                fontFamily: 'Ahem',
                letterSpacing: 1.5,
                wordSpacing: 3.25,
              ),
            ),
          ),
          child: Builder(
            builder: (context) {
              result = NovelReaderNativeRenderEnvironment.capture(
                context,
                preferences: NovelReaderPreferences.defaults().copyWith(
                  fontSize: 20,
                  lineHeight: 1,
                  typography: NovelReaderTypographyOverrides(
                    wordSpacing: request,
                  ),
                ),
                resolvedFont: ResolvedFont.system,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  return result;
}

ForumBodyParagraphContent _content(String html, ForumBodyReaderStyle reader) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'word-spacing',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: const ForumBodyStyleResolver().resolve(document, reader),
    path: '0',
  );
}

void main() {
  testWidgets(
    'absence and reset retain contextual word spacing; zero is explicit',
    (tester) async {
      for (final request in [
        null,
        const NovelReaderWordSpacing(
          logicalPixels: 0,
          scope: NovelReaderStyleScope.asDefault,
        ),
        null,
      ]) {
        final environment = await _capture(tester, request);
        expect(
          environment.reader.textStyle.wordSpacing,
          request == null ? 3.25 : 0,
        );
        expect(environment.reader.textStyle.letterSpacing, 1.5);
      }
    },
  );
  for (final scope in NovelReaderStyleScope.values) {
    for (final number in [-2.0, 0.0, 16.0]) {
      testWidgets(
        'word spacing changes real spaces with independent role scope ($scope, $number)',
        (tester) async {
          final environment = await _capture(
            tester,
            NovelReaderWordSpacing(logicalPixels: number, scope: scope),
          );
          for (final tag in ['p', 'h1']) {
            final content = _content(
              '<$tag style="font-size:20px;word-spacing:3px">a b</$tag>',
              environment.reader,
            );
            final forced =
                scope == NovelReaderStyleScope.forceAll ||
                (scope == NovelReaderStyleScope.forceBody && tag == 'p');
            final effective = forced ? number : 3.0;
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: 240,
            );
            addTearDown(layout.dispose);
            expect(content.projection.text, 'a b');
            expect(content.style.textStyle.letterSpacing, 1.5);
            expect(
              layout.lines.single.width,
              closeTo(3 * (20 + 1.5) + effective, .001),
            );
            final space = layout.selectionBoxes(1, 2).single;
            expect(
              space.right - space.left,
              closeTo(20 + 1.5 + effective, .001),
            );
          }
        },
      );
    }
  }
  testWidgets('word spacing does not simulate Chinese character spacing', (
    tester,
  ) async {
    final widths = <double>[];
    for (final number in [-2.0, 0.0, 16.0]) {
      final environment = await _capture(
        tester,
        NovelReaderWordSpacing(logicalPixels: number),
      );
      final content = _content('<p>中文かな日文</p>', environment.reader);
      final layout = ForumBodyParagraphLayout.create(
        content: content,
        width: 400,
      );
      addTearDown(layout.dispose);
      expect(content.projection.text, '中文かな日文');
      widths.add(layout.lines.single.width);
    }
    expect(widths[0], widths[1]);
    expect(widths[2], widths[1]);
  });
  for (final number in [-2.0, 16.0]) {
    testWidgets('logical word spacing is not scaled again ($number)', (
      tester,
    ) async {
      final environment = await _capture(
        tester,
        NovelReaderWordSpacing(logicalPixels: number),
        scaler: const TextScaler.linear(2),
      );
      final content = _content('<p>a b</p>', environment.reader);
      final layout = ForumBodyParagraphLayout.create(
        content: content,
        width: 240,
        textScaler: environment.textScaler,
      );
      addTearDown(layout.dispose);
      expect(layout.lines.single.width, closeTo(3 * (40 + 1.5) + number, .001));
    });
  }
  for (final direction in TextDirection.values) {
    testWidgets('Unicode spaces and bidi use native shaping ($direction)', (
      tester,
    ) async {
      final environment = await _capture(
        tester,
        const NovelReaderWordSpacing(logicalPixels: 7.5),
        direction: direction,
      );
      for (final text in [
        'a\u00a0b',
        'A👩‍👩‍👧‍👦 e\u0301B',
        'السَّلَامُ عَلَيْكُمْ',
      ]) {
        final content = _content('<p>$text</p>', environment.reader);
        final layout = ForumBodyParagraphLayout.create(
          content: content,
          width: 600,
        );
        addTearDown(layout.dispose);
        final control = TextPainter(
          text: TextSpan(text: text, style: content.style.textStyle),
          textAlign: content.style.textAlign,
          textDirection: direction,
        )..layout(minWidth: 600, maxWidth: 600);
        addTearDown(control.dispose);
        expect(content.projection.text, text);
        for (final range in content.projection.graphemeRanges(
          startUtf16: 0,
          endUtf16: text.length,
        )) {
          expect(
            layout
                .selectionBoxes(range.startUtf16, range.endUtf16)
                .map((b) => b.toRect())
                .toList(),
            control
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: range.startUtf16,
                    extentOffset: range.endUtf16,
                  ),
                )
                .map((b) => b.toRect())
                .toList(),
          );
        }
      }
    });
  }
}
