import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';

const _font = ResolvedFont(id: 'imported-a', fontFamily: 'fixture-native-font');

Future<NovelReaderNativeRenderEnvironment> _capture(
  WidgetTester tester, {
  NovelReaderPreferences? preferences,
  ResolvedFont font = ResolvedFont.system,
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
  ForumBodyStylePolicy? policy,
}) async {
  late NovelReaderNativeRenderEnvironment result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: scaler),
      child: Directionality(
        textDirection: direction,
        child: Theme(
          data: theme ?? ThemeData.light(),
          child: DefaultTextStyle(
            // Retiring imported styles must not leak into a fresh system layout.
            style: const TextStyle(fontFamily: 'stale-imported', fontSize: 91),
            child: Builder(
              builder: (context) {
                result = NovelReaderNativeRenderEnvironment.capture(
                  context,
                  preferences: preferences ?? NovelReaderPreferences.defaults(),
                  resolvedFont: font,
                  policy: policy,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    ),
  );
  return result;
}

void main() {
  setUpAll(() async {
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });
  for (final scope in NovelReaderStyleScope.values) {
    testWidgets('persistable em request applies actual role geometry $scope', (
      tester,
    ) async {
      final environment = await _capture(
        tester,
        preferences: NovelReaderPreferences.defaults().copyWith(
          fontSize: 20,
          typography: NovelReaderTypographyOverrides(
            firstLineIndent: NovelReaderFirstLineIndent(em: 2, scope: scope),
          ),
        ),
        theme: ThemeData.light().copyWith(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontFamily: 'Ahem')),
        ),
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.asDefault,
        }),
      );
      expect(
        environment.reader.firstLineIndent,
        const ForumBodyLength(2, ForumBodyLengthUnit.em),
      );
      expect(
        environment.reader.policy.values[ForumBodyStyleProperty.fontSize],
        ForumBodyStyleScope.asDefault,
      );
      for (final tag in ['p', 'h1']) {
        final doc = const ForumBodyParser().parse(
          html: '<$tag style="font-size:20px;text-indent:10px">abcd</$tag>',
          sourceId: 'indent-ui',
          conversionIdentity: 'none',
        );
        final input = const ForumBodyParagraphContentBuilder().build(
          document: doc,
          styles: const ForumBodyStyleResolver().resolve(
            doc,
            environment.reader,
          ),
          path: '0',
        );
        final layout = ForumBodyParagraphLayout.create(
          content: input,
          width: 200,
        );
        addTearDown(layout.dispose);
        final forced =
            scope == NovelReaderStyleScope.forceAll ||
            (scope == NovelReaderStyleScope.forceBody && tag == 'p');
        expect(
          layout.selectionBoxes(0, 1).single.left,
          closeTo(forced ? 40 : 10, .001),
        );
      }
    });
  }

  testWidgets(
    'explicit author-zero and absent request share effective native inputs',
    (tester) async {
      final initial = await _capture(tester);
      final author = await _capture(
        tester,
        preferences: NovelReaderPreferences.defaults().copyWith(
          typography: const NovelReaderTypographyOverrides(
            firstLineIndent: NovelReaderFirstLineIndent.followAuthor(),
          ),
        ),
      );
      expect(author.reader.firstLineIndent, initial.reader.firstLineIndent);
      for (final property in ForumBodyStyleProperty.values) {
        expect(
          author.reader.policy.values[property] ??
              ForumBodyStyleScope.asDefault,
          initial.reader.policy.values[property] ??
              ForumBodyStyleScope.asDefault,
        );
      }
    },
  );
  testWidgets('current reading preferences become unscaled native inputs', (
    tester,
  ) async {
    final environment = await _capture(
      tester,
      preferences: NovelReaderPreferences.defaults().copyWith(
        fontFamily: _font.id,
        fontSize: 21,
        lineHeight: 1.75,
        fontWeight: 700,
        paragraphSpacing: 17,
        firstLineIndent: 32,
        textAlign: NovelReaderTextAlignMode.justify,
        themePreset: NovelReaderThemePreset.sepia,
      ),
      font: _font,
      scaler: const TextScaler.linear(2),
      direction: TextDirection.rtl,
    );
    final reader = environment.reader;
    expect(reader.textStyle.fontFamily, _font.fontFamily);
    expect(reader.fontRevision, _font.cacheKey);
    expect(reader.textStyle.fontSize, 21);
    expect(reader.textStyle.height, 1.75);
    expect(reader.textStyle.fontWeight, FontWeight.w700);
    expect(reader.textStyle.color, const Color(0xFF4C3A21));
    expect(reader.linkColor, const Color(0xFF6A55A3));
    expect(reader.textStyle.inherit, isFalse);
    expect(reader.paragraphAfter, 17);
    expect(reader.firstLineIndent, const ForumBodyLength(32));
    expect(reader.textAlign, TextAlign.justify);
    expect(reader.textDirection, TextDirection.rtl);
    expect(environment.textScaler.scale(21), 42);
  });

  testWidgets('system fallback uses the fresh theme, not the retiring family', (
    tester,
  ) async {
    final theme = ThemeData.light().copyWith(
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontFamily: 'scene-system',
          fontFamilyFallback: ['scene-fallback'],
        ),
      ),
    );
    final imported = await _capture(
      tester,
      preferences: NovelReaderPreferences.defaults().copyWith(
        fontFamily: _font.id,
      ),
      font: _font,
      theme: theme,
    );
    final system = await _capture(tester, theme: theme);
    expect(imported.reader.textStyle.fontFamily, _font.fontFamily);
    expect(system.reader.textStyle.fontFamily, 'scene-system');
    expect(system.reader.textStyle.fontFamilyFallback, ['scene-fallback']);
    expect(system.reader.fontRevision, ResolvedFont.system.cacheKey);
  });

  testWidgets('a pending or missing runtime family cannot publish a layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            for (final font in [
              ResolvedFont.system,
              const ResolvedFont(id: 'imported-a', fontFamily: null),
              const ResolvedFont(id: 'imported-a', fontFamily: '  '),
            ]) {
              expect(
                () => NovelReaderNativeRenderEnvironment.capture(
                  context,
                  preferences: NovelReaderPreferences.defaults().copyWith(
                    fontFamily: _font.id,
                  ),
                  resolvedFont: font,
                ),
                throwsStateError,
              );
            }
            expect(
              () => NovelReaderNativeRenderEnvironment.capture(
                context,
                preferences: NovelReaderPreferences.defaults(),
                resolvedFont: const ResolvedFont(
                  id: FontIdentity.system,
                  fontFamily: 'stale-imported',
                ),
              ),
              throwsStateError,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native layout retains nonlinear scale at each author font size',
    (tester) async {
      const scaler = _NonlinearScaler();
      final environment = await _capture(
        tester,
        preferences: NovelReaderPreferences.defaults().copyWith(
          fontSize: 10,
          lineHeight: 1,
        ),
        scaler: scaler,
      );
      expect(environment.textScaler, same(scaler));
      final document = const ForumBodyParser().parse(
        html: '<p style="margin:0">a<br><span style="font-size:20px">b</span></p>',
        sourceId: 'fixture',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        environment.reader,
      );
      final content = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 50000,
      );
      addTearDown(cache.close);
      final native = cache.acquire(
        content: content,
        width: 200,
        textScaler: environment.textScaler,
      );
      final flat = cache.acquire(
        content: content,
        width: 200,
        textScaler: const TextScaler.linear(2),
      );
      addTearDown(native.release);
      addTearDown(flat.release);
      expect(styles.byPath['0/0']!.textStyle.fontSize, 10);
      expect(styles.byPath['0/2/0']!.textStyle.fontSize, 20);
      expect(native.layout, isNot(same(flat.layout)));
      expect(native.layout.height, lessThan(flat.layout.height));
    },
  );

  testWidgets(
    'imported family beats author families while code stays monospace',
    (tester) async {
      final policy = ForumBodyStylePolicy({
        ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
      });
      final environment = await _capture(
        tester,
        preferences: NovelReaderPreferences.defaults().copyWith(
          fontFamily: _font.id,
          fontSize: 18,
        ),
        font: _font,
        policy: policy,
      );
      final document = const ForumBodyParser().parse(
        html:
            '<p style="font-family:missing;font-size:30px">body</p>'
            '<code style="font-family:missing;font-size:13px">code</code>',
        sourceId: 'fixture',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        environment.reader,
      );
      expect(environment.reader.policy, same(policy));
      expect(styles.byPath['0/0']!.textStyle.fontFamily, _font.fontFamily);
      expect(styles.byPath['0/0']!.textStyle.fontSize, 18);
      expect(styles.byPath['1/0']!.textStyle.fontFamily, 'monospace');
      expect(styles.byPath['1/0']!.textStyle.fontSize, 13);
    },
  );
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 10 ? fontSize * 2 : fontSize * 1.2;
  @override
  double get textScaleFactor =>
      throw StateError('Linear flattening is invalid');
}
