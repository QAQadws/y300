import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_typography_adapter.dart';

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester,
  NovelReaderFontWeight? weight, {
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
                letterSpacing: 0,
                wordSpacing: 0,
              ),
            ),
          ),
          child: Builder(
            builder: (context) {
              result = NovelReaderNativeRenderEnvironment.capture(
                context,
                preferences: NovelReaderPreferences.defaults().copyWith(
                  fontSize: 20,
                  typography: NovelReaderTypographyOverrides(
                    fontWeight: weight,
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

void main() {
  test(
    'absence retains caller policy; explicit default can undo a forced base',
    () {
      final base = ForumBodyStylePolicy({
        ForumBodyStyleProperty.fontWeight: ForumBodyStyleScope.forceAll,
      });
      final prefs = NovelReaderPreferences.defaults();
      expect(
        resolveNovelReaderNativeTypography(prefs, base).policy,
        same(base),
      );
      final explicit = resolveNovelReaderNativeTypography(
        prefs.copyWith(
          typography: const NovelReaderTypographyOverrides(
            fontWeight: NovelReaderFontWeight(
              value: 400,
              scope: NovelReaderStyleScope.asDefault,
            ),
          ),
        ),
        base,
      );
      expect(
        explicit.policy.values[ForumBodyStyleProperty.fontWeight],
        ForumBodyStyleScope.asDefault,
      );
      expect(
        () => resolveNovelReaderNativeTypography(
          prefs.copyWith(
            typography: const NovelReaderTypographyOverrides(
              fontWeight: NovelReaderFontWeight(value: 550),
            ),
          ),
          base,
        ),
        throwsArgumentError,
      );
    },
  );
  for (final scope in [null, ...NovelReaderStyleScope.values]) {
    testWidgets(
      'weight scope preserves role boundaries and inherited author values ($scope)',
      (tester) async {
        final environment = await _capture(
          tester,
          scope == null
              ? null
              : NovelReaderFontWeight(value: 700, scope: scope),
        );
        final document = const ForumBodyParser().parse(
          html:
              '<div style="font-weight:300"><p id="body">plain'
              '<strong id="strong">bold<span id="nested" style="font-weight:normal">still emphasized</span></strong>'
              '<ruby id="ruby">base<rt id="annotation">note</rt></ruby><code id="inlineCode">code</code></p>'
              '<h2 id="heading" style="font-weight:200">title</h2><pre id="code">code</pre>'
              '<blockquote id="quote">quote</blockquote><ul><li id="list">list</li></ul></div>',
          sourceId: 'weight-roles',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          environment.reader,
        );
        final byId = <String, ForumBodyResolvedStyle>{
          for (final node in document.descendants.whereType<ForumBodyElement>())
            if (node.attributes['id'] case final String id)
              id: styles.byPath[node.path]!,
        };
        final forced =
            scope == NovelReaderStyleScope.forceBody ||
            scope == NovelReaderStyleScope.forceAll;
        final all = scope == NovelReaderStyleScope.forceAll;
        expect(
          byId['body']!.textStyle.fontWeight,
          forced ? FontWeight.w700 : FontWeight.w300,
        );
        expect(
          byId['strong']!.textStyle.fontWeight,
          forced ? FontWeight.w900 : FontWeight.w400,
        );
        expect(
          byId['nested']!.textStyle.fontWeight,
          forced ? FontWeight.w900 : FontWeight.w400,
        );
        expect(
          byId['ruby']!.textStyle.fontWeight,
          forced ? FontWeight.w700 : FontWeight.w300,
        );
        expect(
          byId['heading']!.textStyle.fontWeight,
          all ? FontWeight.w900 : FontWeight.w200,
        );
        for (final id in [
          'annotation',
          'inlineCode',
          'code',
          'quote',
          'list',
        ]) {
          expect(
            byId[id]!.textStyle.fontWeight,
            all ? FontWeight.w700 : FontWeight.w300,
            reason: id,
          );
        }
        expect(byId['code']!.textStyle.fontFamily, 'monospace');
      },
    );
  }
  for (var number = 100; number <= 800; number += 100) {
    testWidgets(
      'base $number reserves a heavier emphasis without cumulative nesting',
      (tester) async {
        final environment = await _capture(
          tester,
          NovelReaderFontWeight(value: number),
        );
        final document = const ForumBodyParser().parse(
          html: '<p>a<strong id="strong">b<span id="nested">c</span><b id="b">d</b></strong></p>',
          sourceId: 'weight-emphasis',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          environment.reader,
        );
        for (final node
            in document.descendants.whereType<ForumBodyElement>().where(
              (n) => n.attributes.containsKey('id'),
            )) {
          final actual = styles.byPath[node.path]!.textStyle.fontWeight!.value;
          expect(
            actual,
            number < 400
                ? 400
                : number < 600
                ? 700
                : 900,
          );
          expect(actual, greaterThan(number));
        }
        final reset = await _capture(tester, null);
        expect(reset.reader.textStyle.fontWeight, FontWeight.w400);
      },
    );
  }
  for (final direction in TextDirection.values) {
    for (final scaled in [false, true]) {
      testWidgets(
        'real mixed-weight glyph geometry matches native shaping ($direction, $scaled)',
        (tester) async {
          final environment = await _capture(
            tester,
            const NovelReaderFontWeight(value: 700),
            direction: direction,
            scaler: scaled ? const _NonlinearScaler() : TextScaler.noScaling,
          );
          final document = const ForumBodyParser().parse(
            html: '<p style="font-weight:200">a<strong>b</strong></p>',
            sourceId: 'weight-geometry',
            conversionIdentity: 'none',
          );
          final content = const ForumBodyParagraphContentBuilder().build(
            document: document,
            styles: const ForumBodyStyleResolver().resolve(
              document,
              environment.reader,
            ),
            path: '0',
          );
          final layout = ForumBodyParagraphLayout.create(
            content: content,
            width: 200,
            textScaler: environment.textScaler,
          );
          addTearDown(layout.dispose);
          final reference = TextPainter(
            text: TextSpan(
              style: environment.reader.textStyle,
              children: const [
                TextSpan(
                  text: 'a',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: 'b',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            textDirection: direction,
            textScaler: environment.textScaler,
          )..layout(minWidth: 200, maxWidth: 200);
          addTearDown(reference.dispose);
          for (var i = 0; i < 2; i++) {
            expect(
              layout.selectionBoxes(i, i + 1).map((b) => b.toRect()).toList(),
              reference
                  .getBoxesForSelection(
                    TextSelection(baseOffset: i, extentOffset: i + 1),
                  )
                  .map((b) => b.toRect())
                  .toList(),
            );
          }
          expect(content.projection.text, 'ab');
        },
      );
    }
  }
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 20 ? size * 1.6 : size * 1.2;
  @override
  double get textScaleFactor =>
      throw StateError('Do not flatten nonlinear scale');
}
