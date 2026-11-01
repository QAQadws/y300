import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester,
  NovelReaderStyleScope? scope, {
  bool forceSize = false,
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
                  lineHeight: 1.8,
                  typography: NovelReaderTypographyOverrides(
                    lineHeightScope: scope,
                    fontSizeScope: forceSize
                        ? NovelReaderStyleScope.forceBody
                        : null,
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
    for (final forceSize in [false, true]) {
      testWidgets(
        'line-height role inheritance is independent of size ($scope, $forceSize)',
        (tester) async {
          final environment = await _capture(
            tester,
            scope,
            forceSize: forceSize,
          );
          final document = const ForumBodyParser().parse(
            html:
                '<div style="font-size:20px;line-height:32px">'
                '<p id="body" style="font-size:12px;line-height:24px">a'
                '<span id="large" style="font-size:200%">b</span>'
                '<ruby>d<rt id="annotation" style="line-height:8px">r</rt></ruby></p>'
                '<h2 id="heading">title</h2><pre id="code">code</pre>'
                '<blockquote id="quote">quote</blockquote><ul><li id="list">list</li></ul></div>',
            sourceId: 'line-height-roles',
            conversionIdentity: 'none',
          );
          final styles = const ForumBodyStyleResolver().resolve(
            document,
            environment.reader,
          );
          final byId = <String, ForumBodyResolvedStyle>{};
          for (final node
              in document.descendants.whereType<ForumBodyElement>()) {
            final id = node.attributes['id'];
            if (id != null) byId[id] = styles.byPath[node.path]!;
          }
          final body =
              scope == NovelReaderStyleScope.forceBody ||
              scope == NovelReaderStyleScope.forceAll;
          final all = scope == NovelReaderStyleScope.forceAll;
          void height(String id, bool forced, double pixels) {
            expect(byId[id]!.lineHeight.factor, forced ? 1.8 : null);
            expect(byId[id]!.lineHeight.pixels, forced ? null : pixels);
          }

          height('body', body, 24);
          height('large', body, 24);
          for (final id in ['heading', 'code', 'quote', 'list']) {
            height(id, all, 32);
          }
          height('annotation', all, 8);
          expect(byId['body']!.textStyle.fontSize, forceSize ? 20 : 12);
          expect(byId['large']!.textStyle.fontSize, forceSize ? 20 : 24);
          expect(byId['annotation']!.textStyle.fontSize, 6);
          expect(byId['heading']!.textStyle.fontWeight, FontWeight.w700);
          expect(byId['code']!.textStyle.fontFamily, 'monospace');
        },
      );
    }
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'line-height policy sets real native baselines once ($scope, $scale)',
        (tester) async {
          final environment = await _capture(
            tester,
            scope,
            scaler: TextScaler.linear(scale),
          );
          final document = const ForumBodyParser().parse(
            html: '<p style="font-size:20px;line-height:24px">a<br>b</p>',
            sourceId: 'line-height-native',
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
          final stride = (forced ? 36 : 24) * scale;
          expect(layout.lines, hasLength(2));
          expect(
            layout.lines[1].baseline - layout.lines[0].baseline,
            closeTo(stride, .001),
          );
          expect(layout.height, closeTo(stride * 2, .001));
          expect(content.projection.text, 'a\nb');
          for (final offset in [0, 2]) {
            final box = layout.selectionBoxes(offset, offset + 1).single;
            expect(box.right - box.left, closeTo(20 * scale, .001));
            expect(box.top, greaterThanOrEqualTo(0));
            expect(box.bottom, lessThanOrEqualTo(layout.height));
          }
        },
      );
    }
  }
}
