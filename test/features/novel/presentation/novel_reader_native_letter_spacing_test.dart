import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester,
  NovelReaderLetterSpacing? request, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
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
                letterSpacing: .5,
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
                    letterSpacing: request,
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
    sourceId: 'letter-spacing',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: const ForumBodyStyleResolver().resolve(document, reader),
    path: '0',
  );
}

void main() {
  testWidgets('absence and reset preserve theme spacing; zero is explicit', (
    tester,
  ) async {
    for (final request in [
      null,
      const NovelReaderLetterSpacing(
        logicalPixels: 0,
        scope: NovelReaderStyleScope.asDefault,
      ),
      null,
    ]) {
      final environment = await _capture(tester, request);
      expect(
        environment.reader.textStyle.letterSpacing,
        request == null ? .5 : 0,
      );
      expect(environment.reader.textStyle.wordSpacing, 3.25);
    }
  });
  for (final scope in NovelReaderStyleScope.values) {
    for (final number in [-2.0, 0.0, 8.0]) {
      testWidgets(
        'actual letter geometry obeys reader/author scope ($scope, $number)',
        (tester) async {
          final environment = await _capture(
            tester,
            NovelReaderLetterSpacing(logicalPixels: number, scope: scope),
          );
          for (final tag in ['p', 'h1']) {
            final content = _content(
              '<$tag style="font-size:20px;letter-spacing:3px">abcd</$tag>',
              environment.reader,
            );
            final forced =
                scope == NovelReaderStyleScope.forceAll ||
                (scope == NovelReaderStyleScope.forceBody && tag == 'p');
            final effective = forced ? number : 3.0;
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: 200,
            );
            addTearDown(layout.dispose);
            expect(content.projection.text, 'abcd');
            expect(content.style.textStyle.wordSpacing, 3.25);
            expect(
              layout.lines.single.width,
              closeTo(4 * (20 + effective), .001),
            );
          }
        },
      );
    }
  }
  for (final number in [-2.0, 8.0]) {
    testWidgets(
      'logical pixel spacing is not multiplied by font scale ($number)',
      (tester) async {
        final environment = await _capture(
          tester,
          NovelReaderLetterSpacing(logicalPixels: number),
          scaler: const TextScaler.linear(2),
        );
        final content = _content('<p>abcd</p>', environment.reader);
        final layout = ForumBodyParagraphLayout.create(
          content: content,
          width: 240,
          textScaler: environment.textScaler,
        );
        addTearDown(layout.dispose);
        expect(layout.lines.single.width, closeTo(4 * (40 + number), .001));
      },
    );
  }
  for (final direction in TextDirection.values) {
    for (final number in [-2.0, 8.0]) {
      testWidgets(
        'native graphemes and bidi shaping remain intact ($direction, $number)',
        (tester) async {
          final environment = await _capture(
            tester,
            NovelReaderLetterSpacing(logicalPixels: number),
            direction: direction,
          );
          for (final text in [
            '中文かな日文',
            'A👩‍👩‍👧‍👦e\u0301B',
            'السَّلَامُ عَلَيْكُمْ',
          ]) {
            final content = _content('<p>$text</p>', environment.reader);
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: 600,
            );
            addTearDown(layout.dispose);
            final inset = number < 0 ? -number : 0.0;
            expect(layout.horizontalInset, inset);
            final control = TextPainter(
              text: TextSpan(text: text, style: content.style.textStyle),
              textAlign: content.style.textAlign,
              textDirection: direction,
            )..layout(minWidth: 600 - 2 * inset, maxWidth: 600 - 2 * inset);
            addTearDown(control.dispose);
            expect(content.projection.text, text);
            for (final range in content.projection.graphemeRanges(
              startUtf16: 0,
              endUtf16: text.length,
            )) {
              final actual = layout.selectionBoxes(
                range.startUtf16,
                range.endUtf16,
              );
              final expected = control.getBoxesForSelection(
                TextSelection(
                  baseOffset: range.startUtf16,
                  extentOffset: range.endUtf16,
                ),
              );
              expect(
                actual.map((box) => box.toRect()).toList(),
                expected
                    .map((box) => box.toRect().shift(Offset(inset, 0)))
                    .toList(),
              );
            }
          }
        },
      );
    }
  }
}
