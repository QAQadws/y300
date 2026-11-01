import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester,
  NovelReaderStyleScope? scope, {
  TextScaler scaler = TextScaler.noScaling,
}) async {
  late NovelReaderNativeRenderEnvironment result;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
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
                  lineHeight: 1,
                  typography: NovelReaderTypographyOverrides(
                    fontSizeScope: scope,
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
  for (final scope in [null, ...NovelReaderStyleScope.values]) {
    testWidgets(
      'font-size policy preserves excluded role inheritance ($scope)',
      (tester) async {
        final environment = await _capture(tester, scope);
        final document = const ForumBodyParser().parse(
          html:
              '<div style="font-size:36px"><p id="body" style="font-size:12px">a'
              '<span id="relative" style="font-size:200%">b</span><small id="small">c</small>'
              '<ruby id="base">d<rt id="annotation">r</rt></ruby><strong id="strong">bold</strong></p>'
              '<h2 id="heading">title</h2><pre id="code">code</pre>'
              '<blockquote id="quote">quote</blockquote><ul><li id="list">list</li></ul></div>',
          sourceId: 'font-size-roles',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          environment.reader,
        );
        final byId = <String, ForumBodyResolvedStyle>{};
        for (final node in document.descendants.whereType<ForumBodyElement>()) {
          final id = node.attributes['id'];
          if (id != null) {
            byId[id] = styles.byPath[node.path]!;
          }
        }
        final forceBody =
            scope == NovelReaderStyleScope.forceBody ||
            scope == NovelReaderStyleScope.forceAll;
        final forceAll = scope == NovelReaderStyleScope.forceAll;
        expect(byId['body']!.textStyle.fontSize, forceBody ? 20 : 12);
        expect(byId['relative']!.textStyle.fontSize, forceBody ? 20 : 24);
        expect(
          byId['small']!.textStyle.fontSize,
          closeTo(forceBody ? 20 : 10.2, .001),
        );
        expect(byId['base']!.textStyle.fontSize, forceBody ? 20 : 12);
        expect(byId['annotation']!.textStyle.fontSize, forceAll ? 20 : 6);
        expect(byId['heading']!.textStyle.fontSize, forceAll ? 20 : 54);
        for (final id in ['code', 'quote', 'list']) {
          expect(byId[id]!.textStyle.fontSize, forceAll ? 20 : 36);
        }
        expect(byId['code']!.textStyle.fontFamily, 'monospace');
        expect(byId['heading']!.textStyle.fontWeight, FontWeight.w700);
        expect(byId['strong']!.textStyle.fontWeight, FontWeight.w700);
      },
    );
    for (final scaled in [false, true]) {
      testWidgets(
        'font-size policy controls actual glyph geometry once ($scope, scaled=$scaled)',
        (tester) async {
          final environment = await _capture(
            tester,
            scope,
            scaler: scaled ? const _NonlinearScaler() : TextScaler.noScaling,
          );
          final document = const ForumBodyParser().parse(
            html: '<p style="font-size:12px">a<span style="font-size:200%">b</span></p>',
            sourceId: 'font-size-native',
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
            width: 240,
            textScaler: environment.textScaler,
          );
          addTearDown(layout.dispose);
          final forced =
              scope == NovelReaderStyleScope.forceBody ||
              scope == NovelReaderStyleScope.forceAll;
          expect(
            layout.lines.single.width,
            closeTo(forced ? (scaled ? 80 : 40) : (scaled ? 52.8 : 36), .002),
          );
          expect(content.projection.text, 'ab');
        },
      );
    }
  }
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 20 ? size * 2 : size * 1.2;
  @override
  double get textScaleFactor =>
      throw StateError('Do not flatten nonlinear scale');
}
