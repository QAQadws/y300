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
  for (final foreground in NovelReaderStyleScope.values) {
    for (final background in NovelReaderStyleScope.values) {
      testWidgets(
        'independent author colors resolve native roles and link exceptions ($foreground/$background)',
        (tester) async {
          final environment = await _capture(
            tester,
            preferences: NovelReaderPreferences.defaults().copyWith(
              colors: NovelReaderColorOverrides(
                foreground: 0x203040,
                background: 0xe8f0d8,
                foregroundScope: foreground,
                backgroundScope: background,
              ),
            ),
            policy: ForumBodyStylePolicy({
              ForumBodyStyleProperty.lineHeight: ForumBodyStyleScope.forceAll,
            }),
          );
          expect(
            environment.reader.policy.values[ForumBodyStyleProperty.lineHeight],
            ForumBodyStyleScope.forceAll,
          );
          final document = const ForumBodyParser().parse(
            html:
                '<div style="color:#b22222">'
                '<span id="body" style="background:#ffe000">body<strong id="strong">bold</strong></span>'
                '<h2 id="heading" style="color:#b22222;background:#ffe000">title</h2>'
                '<blockquote id="quote" style="color:#b22222;background:#ffe000">quote</blockquote>'
                '<code id="code" style="color:#b22222;background:#ffe000">code</code>'
                '<ul><li id="list" style="color:#b22222;background:#ffe000">list</li></ul>'
                '<ruby id="base" style="background:#ffe000">base<rt id="rt" style="background:inherit">note</rt></ruby>'
                '<a id="link" href="https://example.invalid" style="color:#008000;background:#ffe000">'
                '<span id="linkchild" style="color:#0000ff">link</span></a></div>',
            sourceId: 'author-color-policy',
            conversionIdentity: 'none',
          );
          final styles = const ForumBodyStyleResolver().resolve(
            document,
            environment.reader,
          );
          ForumBodyResolvedStyle byId(String id) =>
              styles.byPath[document.descendants
                  .whereType<ForumBodyElement>()
                  .firstWhere((e) => e.attributes['id'] == id)
                  .path]!;
          for (final id in [
            'body',
            'heading',
            'quote',
            'code',
            'list',
            'base',
            'rt',
          ]) {
            final style = byId(id);
            final body = style.role == ForumBodyTextRole.body;
            final forceInk =
                foreground == NovelReaderStyleScope.forceAll ||
                (foreground == NovelReaderStyleScope.forceBody && body);
            final forceBackground =
                background == NovelReaderStyleScope.forceAll ||
                (background == NovelReaderStyleScope.forceBody && body);
            expect(
              style.textStyle.color,
              forceInk ? const Color(0xff203040) : const Color(0xffb22222),
              reason: id,
            );
            if (forceBackground) {
              expect(style.ownBackground, isNull, reason: id);
              expect(style.boxBackground, isNull, reason: id);
              expect(
                style.textStyle.backgroundColor,
                anyOf(isNull, const Color(0x00000000)),
                reason: id,
              );
            } else {
              expect(
                style.ownBackground ??
                    style.boxBackground ??
                    style.textStyle.backgroundColor,
                const Color(0xffffe000),
                reason: id,
              );
            }
          }
          expect(byId('link').textStyle.color, const Color(0xff008000));
          expect(byId('linkchild').textStyle.color, const Color(0xff0000ff));
          expect(byId('strong').textStyle.fontWeight, FontWeight.w700);
          expect(environment.backgroundColor, const Color(0xffe8f0d8));
          expect(styles.issues, isEmpty);
        },
      );
    }
  }
  testWidgets(
    'absent author scopes inherit base policy and explicit preserve overrides it without changing preset',
    (tester) async {
      final policy = ForumBodyStylePolicy({
        ForumBodyStyleProperty.foreground: ForumBodyStyleScope.forceAll,
        ForumBodyStyleProperty.background: ForumBodyStyleScope.forceAll,
      });
      final baseline = await _capture(tester, policy: policy);
      expect(baseline.reader.policy, same(policy));
      final preserved = await _capture(
        tester,
        policy: policy,
        preferences: NovelReaderPreferences.defaults().copyWith(
          colors: const NovelReaderColorOverrides(
            foregroundScope: NovelReaderStyleScope.asDefault,
            backgroundScope: NovelReaderStyleScope.asDefault,
          ),
        ),
      );
      expect(preserved.reader.textStyle, baseline.reader.textStyle);
      expect(preserved.reader.linkColor, baseline.reader.linkColor);
      expect(preserved.backgroundColor, baseline.backgroundColor);
      expect(
        preserved.reader.policy.values[ForumBodyStyleProperty.foreground],
        ForumBodyStyleScope.asDefault,
      );
      expect(
        preserved.reader.policy.values[ForumBodyStyleProperty.background],
        ForumBodyStyleScope.asDefault,
      );
    },
  );
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
          layout.selectionBoxes(0, 1).single.left - layout.horizontalInset,
          closeTo(forced ? 40 : 10, .001),
        );
        expect(
          layout.firstLineIndent.appliedAdvance,
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
  for (final scope in NovelReaderStyleScope.values) {
    testWidgets(
      'spacing scope preserves author roles and horizontal margins $scope',
      (tester) async {
        final environment = await _capture(
          tester,
          preferences: NovelReaderPreferences.defaults().copyWith(
            typography: NovelReaderTypographyOverrides(
              firstLineIndent: const NovelReaderFirstLineIndent(em: 1.5),
              paragraphSpacing: NovelReaderParagraphSpacing(
                before: 12,
                after: 31,
                scope: scope,
              ),
            ),
          ),
        );
        expect(
          environment.reader.firstLineIndent,
          const ForumBodyLength(1.5, ForumBodyLengthUnit.em),
        );
        for (final tag in ['p', 'h1']) {
          final document = const ForumBodyParser().parse(
            html: '<$tag style="margin:1px 2px 3px 4px">text</$tag>',
            sourceId: 'spacing-scope',
            conversionIdentity: 'none',
          );
          final style = const ForumBodyStyleResolver()
              .resolve(document, environment.reader)
              .byPath['0']!;
          final forced =
              scope == NovelReaderStyleScope.forceAll ||
              (scope == NovelReaderStyleScope.forceBody && tag == 'p');
          expect(style.margin.top, ForumBodyLength(forced ? 12 : 1));
          expect(style.margin.bottom, ForumBodyLength(forced ? 31 : 3));
          expect(style.margin.left, const ForumBodyLength(4));
          expect(style.margin.right, const ForumBodyLength(2));
        }
      },
    );
  }
  for (final pageHeight in [250.0, 90.0]) {
    testWidgets(
      'spacing reaches real page geometry, not BR or page edges ($pageHeight)',
      (tester) async {
        final environment = await _capture(
          tester,
          preferences: NovelReaderPreferences.defaults().copyWith(
            fontSize: 20,
            lineHeight: 1,
            typography: const NovelReaderTypographyOverrides(
              paragraphSpacing: NovelReaderParagraphSpacing(
                before: 12,
                after: 31,
              ),
            ),
          ),
          theme: ThemeData.light().copyWith(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontFamily: 'Ahem'),
            ),
          ),
        );
        final document = const ForumBodyParser().parse(
          html: '<p>a<br>b</p><p>c</p>',
          sourceId: 'spacing-native',
          conversionIdentity: 'none',
        );
        final cache = ForumBodyParagraphCache(
          maxEntries: 8,
          maxEstimatedBytes: 1 << 20,
        );
        final session = ForumBodyTextPageSession(
          document: document,
          reader: environment.reader,
          cache: cache,
          limits: const ForumBodyTextPageSessionLimits(
            maxPages: 100,
            maxFragments: 100,
            maxParagraphs: 100,
            maxTextCodeUnits: 10000,
            maxRuns: 1000,
            maxIssuedLeases: 20,
          ),
          layoutId: 'spacing-native',
          width: 200,
          height: pageHeight,
        );
        addTearDown(() {
          session.close();
          cache.close();
        });
        for (var i = 0; !session.isComplete && i < 1000; i++) {
          session.advance(maxEvents: 1, maxLines: 1);
        }
        expect(session.isComplete, isTrue);
        if (pageHeight == 250) {
          expect(session.snapshot.single.fragments.map((f) => f.top).toList(), [
            0,
            20,
            71,
          ]);
          expect(session.snapshot.single.usedHeight, 91);
        } else {
          expect(
            session.snapshot
                .map((p) => p.fragments.map((f) => f.top).toList())
                .toList(),
            [
              [0, 20],
              [0],
            ],
          );
          expect(session.snapshot.map((p) => p.usedHeight).toList(), [40, 20]);
        }
      },
    );
  }
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
