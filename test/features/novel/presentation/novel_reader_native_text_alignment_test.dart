import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_typography_adapter.dart';

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester,
  NovelReaderTextAlignment? alignment, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  NovelReaderFlowMode flow = NovelReaderFlowMode.pagedLtr,
  NovelReaderTextAlignMode legacyAlignment = NovelReaderTextAlignMode.start,
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
                  flowMode: flow,
                  textAlign: legacyAlignment,
                  typography: NovelReaderTypographyOverrides(
                    textAlignment: alignment,
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

TextAlign _align(NovelReaderTextAlignMode mode) => switch (mode) {
  NovelReaderTextAlignMode.start => TextAlign.start,
  NovelReaderTextAlignMode.end => TextAlign.end,
  NovelReaderTextAlignMode.justify => TextAlign.justify,
  NovelReaderTextAlignMode.center => TextAlign.center,
};

void main() {
  test('explicit default retires only the caller alignment policy', () {
    final base = ForumBodyStylePolicy({
      ForumBodyStyleProperty.textAlign: ForumBodyStyleScope.forceAll,
      ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
    });
    final prefs = NovelReaderPreferences.defaults();
    expect(resolveNovelReaderNativeTypography(prefs, base).policy, same(base));
    final overridden = resolveNovelReaderNativeTypography(
      prefs.copyWith(
        typography: const NovelReaderTypographyOverrides(
          textAlignment: NovelReaderTextAlignment(
            mode: NovelReaderTextAlignMode.end,
            scope: NovelReaderStyleScope.asDefault,
          ),
        ),
      ),
      base,
    );
    expect(
      overridden.policy.values[ForumBodyStyleProperty.textAlign],
      ForumBodyStyleScope.asDefault,
    );
    expect(
      overridden.policy.values[ForumBodyStyleProperty.fontSize],
      ForumBodyStyleScope.forceBody,
    );
  });
  for (final scope in [null, ...NovelReaderStyleScope.values]) {
    testWidgets(
      'alignment policy restores author alignment when a body role ends ($scope)',
      (tester) async {
        final env = await _capture(
          tester,
          scope == null
              ? null
              : NovelReaderTextAlignment(
                  mode: NovelReaderTextAlignMode.end,
                  scope: scope,
                ),
        );
        final document = const ForumBodyParser().parse(
          html:
              '<div style="text-align:center"><p id="body" align="right">text'
              '<ruby id="ruby">base<rt id="rt">note</rt></ruby><code id="inlineCode">code</code></p>'
              '<h2 id="heading" align="right">title</h2><pre id="code">code</pre>'
              '<blockquote id="quote">quote</blockquote><ul><li id="list">list</li></ul></div>',
          sourceId: 'alignment-roles',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          env.reader,
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
          byId['body']!.textAlign,
          forced ? TextAlign.end : TextAlign.right,
        );
        expect(
          byId['ruby']!.textAlign,
          forced ? TextAlign.end : TextAlign.right,
        );
        for (final id in ['rt', 'inlineCode', 'heading']) {
          expect(
            byId[id]!.textAlign,
            all ? TextAlign.end : TextAlign.right,
            reason: id,
          );
        }
        for (final id in ['code', 'quote', 'list']) {
          expect(
            byId[id]!.textAlign,
            all ? TextAlign.end : TextAlign.center,
            reason: id,
          );
        }
      },
    );
  }
  for (final direction in TextDirection.values) {
    for (final mode in NovelReaderTextAlignMode.values) {
      for (final scaled in [false, true]) {
        testWidgets(
          'native glyph positions and terminal lines honor $mode/$direction/scaled=$scaled',
          (tester) async {
            final env = await _capture(
              tester,
              NovelReaderTextAlignment(mode: mode),
              direction: direction,
              scaler: scaled ? const _NonlinearScaler() : TextScaler.noScaling,
            );
            final document = const ForumBodyParser().parse(
              html: '<p align="right">a b c d e f g<br>x y<br>z</p>',
              sourceId: 'alignment-native',
              conversionIdentity: 'none',
            );
            final content = const ForumBodyParagraphContentBuilder().build(
              document: document,
              styles: const ForumBodyStyleResolver().resolve(
                document,
                env.reader,
              ),
              path: '0',
            );
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: 150,
              textScaler: env.textScaler,
            );
            addTearDown(layout.dispose);
            expect(content.projection.text, 'a b c d e f g\nx y\nz');
            final control = TextPainter(
              text: TextSpan(
                text: content.projection.text,
                style: env.reader.textStyle,
              ),
              textAlign: _align(mode),
              textDirection: direction,
              textScaler: env.textScaler,
            )..layout(minWidth: 150, maxWidth: 150);
            addTearDown(control.dispose);
            for (var i = 0; i < content.projection.text.length; i++) {
              final selection = TextSelection(
                baseOffset: i,
                extentOffset: i + 1,
              );
              expect(
                layout.selectionBoxes(i, i + 1).map((b) => b.toRect()).toList(),
                control
                    .getBoxesForSelection(selection)
                    .map((b) => b.toRect())
                    .toList(),
                reason: 'display UTF-16 $i',
              );
            }
            if (mode == NovelReaderTextAlignMode.justify) {
              final start = TextPainter(
                text: control.text,
                textAlign: TextAlign.start,
                textDirection: direction,
                textScaler: env.textScaler,
              )..layout(minWidth: 150, maxWidth: 150);
              addTearDown(start.dispose);
              // Both an explicit BR terminal and the paragraph's final line keep
              // native start alignment instead of stretching to fill the row.
              for (final offset in [
                content.projection.text.indexOf('x'),
                content.projection.text.indexOf('z'),
              ]) {
                final selection = TextSelection(
                  baseOffset: offset,
                  extentOffset: offset + 1,
                );
                expect(
                  control
                      .getBoxesForSelection(selection)
                      .map((b) => b.toRect())
                      .toList(),
                  start
                      .getBoxesForSelection(selection)
                      .map((b) => b.toRect())
                      .toList(),
                );
              }
            }
          },
        );
      }
    }
  }
  testWidgets(
    'local author direction resolves logical alignment after the reader request',
    (tester) async {
      for (final direction in TextDirection.values) {
        final env = await _capture(
          tester,
          const NovelReaderTextAlignment(mode: NovelReaderTextAlignMode.end),
          direction: direction == TextDirection.ltr
              ? TextDirection.rtl
              : TextDirection.ltr,
        );
        final document = const ForumBodyParser().parse(
          html: '<p dir="${direction.name}">abc</p>',
          sourceId: 'author-bidi-alignment',
          conversionIdentity: 'none',
        );
        final content = const ForumBodyParagraphContentBuilder().build(
          document: document,
          styles: const ForumBodyStyleResolver().resolve(document, env.reader),
          path: '0',
        );
        expect(content.style.textDirection, direction);
        final layout = ForumBodyParagraphLayout.create(
          content: content,
          width: 150,
        );
        addTearDown(layout.dispose);
        final reference = TextPainter(
          text: TextSpan(text: 'abc', style: env.reader.textStyle),
          textAlign: TextAlign.end,
          textDirection: direction,
        )..layout(minWidth: 150, maxWidth: 150);
        addTearDown(reference.dispose);
        expect(
          layout.selectionBoxes(0, 1).single.toRect(),
          reference
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1),
              )
              .single
              .toRect(),
        );
      }
    },
  );
  testWidgets(
    'page-turn direction cannot change paragraph bidi or logical end',
    (tester) async {
      for (final direction in TextDirection.values) {
        for (final flow in [
          NovelReaderFlowMode.pagedLtr,
          NovelReaderFlowMode.pagedRtl,
        ]) {
          final env = await _capture(
            tester,
            const NovelReaderTextAlignment(mode: NovelReaderTextAlignMode.end),
            direction: direction,
            flow: flow,
          );
          expect(env.reader.textDirection, direction);
          expect(env.reader.textAlign, TextAlign.end);
        }
      }
      final reset = await _capture(tester, null);
      expect(reset.reader.textAlign, TextAlign.start);
      final legacy = await _capture(
        tester,
        null,
        legacyAlignment: NovelReaderTextAlignMode.center,
      );
      expect(legacy.reader.textAlign, TextAlign.center);
    },
  );
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 20 ? size * 1.6 : size * 1.2;
  @override
  double get textScaleFactor =>
      throw StateError('Do not flatten nonlinear scale');
}
