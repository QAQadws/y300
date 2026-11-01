import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_layout_scope.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';

Future<NovelReaderNativePreparedChapter> _chapter([
  String html = '<p>ab<span style="font-size:40px">cd</span>ef</p>',
]) async => await const DefaultNovelReaderNativePreparationService().prepare(
  episodeId: 'episode',
  sourceId: 'source',
  rawHtml: html,
  semanticDocument: const DiscuzNovelReaderDocumentParser(
    captureSourceProvenance: true,
  ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []),
  cancellation: NovelReaderPaginationCancellationToken(),
) as NovelReaderNativePreparedChapter;

Future<NovelReaderNativeRenderEnvironment> _environment(
  WidgetTester tester, {
  TextStyle style = const TextStyle(
    fontFamily: 'Ahem',
    letterSpacing: 0,
    wordSpacing: 0,
  ),
  NovelReaderPreferences? preferences,
  ResolvedFont font = ResolvedFont.system,
  TextScaler scaler = TextScaler.noScaling,
  ForumBodyStylePolicy? policy,
  Locale locale = const Locale('en'),
  TextDirection direction = TextDirection.ltr,
  Color? foreground,
  Color? background,
}) async {
  late NovelReaderNativeRenderEnvironment captured;
  final theme = ThemeData.light();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: scaler),
      child: Localizations(
        locale: locale,
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Directionality(
          textDirection: direction,
          child: Theme(
            data: theme.copyWith(
              scaffoldBackgroundColor: background,
              colorScheme: theme.colorScheme.copyWith(onSurface: foreground),
              textTheme: TextTheme(bodyMedium: style),
            ),
            child: Builder(
              builder: (context) {
                captured = NovelReaderNativeRenderEnvironment.capture(
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
  return captured;
}

Future<NovelReaderNativeLayoutScope> _scope(
  NovelReaderNativePreparedChapter chapter,
  NovelReaderNativeRenderEnvironment environment, {
  double width = 200,
  double height = 200,
  NovelReaderPaginationCancellationToken? cancellation,
  int maxSizes = 2048,
  int maxIssuedLeases = 128,
}) => NovelReaderNativeLayoutScope.prepare(
  chapter: chapter,
  environment: environment,
  width: width,
  height: height,
  maxIssuedLeases: maxIssuedLeases,
  cancellation: cancellation ?? NovelReaderPaginationCancellationToken(),
  maxScaledFontSizes: maxSizes,
);

const _limits = ForumBodyTextPageSessionLimits(
  maxPages: 100,
  maxFragments: 1000,
  maxParagraphs: 1000,
  maxTextCodeUnits: 20000,
  maxRuns: 10000,
  maxIssuedLeases: 128,
);

void main() {
  testWidgets('page handle capacity is frozen into layout identity', (
    tester,
  ) async {
    final chapter = await _chapter();
    final environment = await _environment(tester);
    final one = await _scope(chapter, environment, maxIssuedLeases: 128);
    final two = await _scope(chapter, environment, maxIssuedLeases: 512);
    expect(one.maxNativeHandlesPerPage, 64);
    expect(two.maxNativeHandlesPerPage, 256);
    expect(one.paginationKey, isNot(two.paginationKey));
    final cache = ForumBodyParagraphCache(
      maxEntries: 8,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    expect(
      () =>
          two.openSession(cache: cache, layoutId: 'mismatch', limits: _limits),
      throwsArgumentError,
    );
    expect(cache.activeLeases, 0);
  });

  testWidgets(
    'equivalent effective inputs have stable keys across objects and policy order',
    (tester) async {
      final chapter = await _chapter();
      final first = await _scope(
        chapter,
        await _environment(
          tester,
          policy: ForumBodyStylePolicy({
            ForumBodyStyleProperty.lineHeight: ForumBodyStyleScope.forceAll,
            ForumBodyStyleProperty.fontWeight: ForumBodyStyleScope.forceBody,
          }),
        ),
      );
      final second = await _scope(
        chapter,
        await _environment(
          tester,
          policy: ForumBodyStylePolicy({
            ForumBodyStyleProperty.fontWeight: ForumBodyStyleScope.forceBody,
            ForumBodyStyleProperty.foreground: ForumBodyStyleScope.asDefault,
            ForumBodyStyleProperty.lineHeight: ForumBodyStyleScope.forceAll,
          }),
        ),
      );
      expect(first.paginationKey, second.paginationKey);
      expect(
        first.paginationKey,
        startsWith(
          'native-${NovelReaderNativeLayoutScope.fingerprintRevision}-',
        ),
      );
      final environment = await _environment(tester);
      final unchangedFonts = await _scope(chapter, environment);
      final fontChanged = await NovelReaderNativeLayoutScope.prepare(
        chapter: chapter,
        environment: environment,
        width: 200,
        height: 200,
        cancellation: NovelReaderPaginationCancellationToken(),
        fontCollectionGeneration: 1,
        maxIssuedLeases: 128,
      );
      expect(fontChanged.paginationKey, isNot(unchangedFonts.paginationKey));
    },
  );

  testWidgets(
    'nonlinear effective author sizes distinguish equal scaler objects and stay frozen',
    (tester) async {
      final chapter = await _chapter();
      final scaler = _BranchScaler(1.6);
      final first = await _scope(
        chapter,
        await _environment(tester, scaler: scaler),
      );
      final other = _BranchScaler(1.8);
      expect(
        scaler,
        other,
        reason: 'Caller equality deliberately omits effective scaling',
      );
      final second = await _scope(
        chapter,
        await _environment(tester, scaler: other),
      );
      expect(first.paginationKey, isNot(second.paginationKey));
      expect(first.textScaler.scale(40), 64);
      scaler.ratio = 2.2;
      expect(first.textScaler.scale(40), 64);
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      final session = first.openSession(
        cache: cache,
        layoutId: 'first',
        limits: _limits,
      );
      addTearDown(() {
        session.close();
        cache.close();
      });
      while (!session.isComplete) {
        session.advance(maxEvents: 32, maxLines: 8);
      }
      expect(session.snapshot, isNotEmpty);
      expect(cache.layoutBuildCount, 1);
      expect(
        () => first.textScaler.scale(17.123),
        throwsA(isA<NovelReaderNativeLayoutInputException>()),
      );
    },
  );

  testWidgets(
    'font and paint values, geometry, direction, locale and reader policy invalidate the key',
    (tester) async {
      final chapter = await _chapter();
      final baseEnvironment = await _environment(tester);
      final base = await _scope(chapter, baseEnvironment);
      final styles = <TextStyle>[
        const TextStyle(fontFamily: 'other'),
        const TextStyle(fontFamilyFallback: ['fallback-a']),
        const TextStyle(fontStyle: FontStyle.italic),
        const TextStyle(letterSpacing: .3),
        const TextStyle(wordSpacing: .7),
        const TextStyle(textBaseline: TextBaseline.ideographic),
        const TextStyle(
          leadingDistribution: TextLeadingDistribution.proportional,
        ),
        const TextStyle(backgroundColor: Colors.red),
        const TextStyle(decoration: TextDecoration.underline),
        const TextStyle(decorationColor: Colors.blue),
        const TextStyle(decorationStyle: TextDecorationStyle.dotted),
        const TextStyle(decorationThickness: 2),
        const TextStyle(
          shadows: [
            Shadow(color: Colors.red, offset: Offset(1, 2), blurRadius: 3),
          ],
        ),
        const TextStyle(fontFeatures: [ui.FontFeature('ss01')]),
        const TextStyle(fontVariations: [ui.FontVariation('wght', 520)]),
        const TextStyle(overflow: TextOverflow.ellipsis),
      ];
      for (final (index, style) in styles.indexed) {
        final scope = await _scope(
          chapter,
          await _environment(
            tester,
            style: const TextStyle(fontFamily: 'Ahem').merge(style),
          ),
        );
        expect(
          scope.paginationKey,
          isNot(base.paginationKey),
          reason: 'Effective style input $index',
        );
      }
      for (final preferences in [
        NovelReaderPreferences.defaults().copyWith(fontSize: 25),
        NovelReaderPreferences.defaults().copyWith(lineHeight: 2),
        NovelReaderPreferences.defaults().copyWith(fontWeight: 700),
        NovelReaderPreferences.defaults().copyWith(
          typography: const NovelReaderTypographyOverrides(
            fontWeight: NovelReaderFontWeight(value: 600),
          ),
        ),
        NovelReaderPreferences.defaults().copyWith(
          typography: const NovelReaderTypographyOverrides(
            fontWeight: NovelReaderFontWeight(
              value: 400,
              scope: NovelReaderStyleScope.forceAll,
            ),
          ),
        ),
        NovelReaderPreferences.defaults().copyWith(paragraphSpacing: 27),
        NovelReaderPreferences.defaults().copyWith(firstLineIndent: 17),
        NovelReaderPreferences.defaults().copyWith(
          textAlign: NovelReaderTextAlignMode.center,
        ),
      ]) {
        final scope = await _scope(
          chapter,
          await _environment(tester, preferences: preferences),
        );
        expect(scope.paginationKey, isNot(base.paginationKey));
      }
      final alternatives = [
        await _scope(chapter, baseEnvironment, width: 201),
        await _scope(chapter, baseEnvironment, height: 201),
        await _scope(
          chapter,
          await _environment(tester, locale: const Locale('ja')),
        ),
        await _scope(
          chapter,
          await _environment(tester, direction: TextDirection.rtl),
        ),
        await _scope(
          chapter,
          await _environment(tester, background: Colors.green),
        ),
        await _scope(
          chapter,
          await _environment(tester, foreground: Colors.red),
        ),
        await _scope(
          chapter,
          await _environment(
            tester,
            policy: ForumBodyStylePolicy({
              ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceAll,
            }),
          ),
        ),
        await _scope(
          chapter,
          await _environment(
            tester,
            font: const ResolvedFont(id: 'imported', fontFamily: 'Ahem'),
            preferences: NovelReaderPreferences.defaults().copyWith(
              fontFamily: 'imported',
            ),
          ),
        ),
        await _scope(await _chapter('<p>changed</p>'), baseEnvironment),
      ];
      expect(
        alternatives.every(
          (scope) => scope.paginationKey != base.paginationKey,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'float color precision and caller style lists are snapshotted rather than rounded or retained',
    (tester) async {
      final chapter = await _chapter();
      const colorA = Color.from(alpha: 1, red: .5001, green: .2, blue: .3);
      const colorB = Color.from(alpha: 1, red: .5002, green: .2, blue: .3);
      expect(colorA.toARGB32(), colorB.toARGB32());
      final first = await _scope(
        chapter,
        await _environment(tester, foreground: colorA),
      );
      final second = await _scope(
        chapter,
        await _environment(tester, foreground: colorB),
      );
      expect(first.paginationKey, isNot(second.paginationKey));
      final features = <ui.FontFeature>[const ui.FontFeature('ss01')];
      final scope = await _scope(
        chapter,
        await _environment(tester, style: TextStyle(fontFeatures: features)),
      );
      features.add(const ui.FontFeature('ss02'));
      expect(scope.reader.textStyle.fontFeatures, hasLength(1));
      expect(
        () => scope.reader.textStyle.fontFeatures!.clear(),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets(
    'large style census crosses the actual worker boundary and stays deterministic',
    (tester) async {
      final html = List.generate(
        600,
        (index) => '<p>$index<span style="font-size:40px">text</span></p>',
      ).join();
      final chapter = await tester.runAsync(() => _chapter(html));
      final environment = await _environment(
        tester,
        scaler: _BranchScaler(1.4),
      );
      final first = await tester.runAsync(() => _scope(chapter!, environment));
      final second = await tester.runAsync(() => _scope(chapter!, environment));
      expect(first!.paginationKey, second!.paginationKey);
      expect(first.textScaler.scale(40), 56);
    },
  );

  testWidgets(
    'invalid geometry, unsupported paint and unbounded size sets fail before a session opens',
    (tester) async {
      final chapter = await _chapter();
      final environment = await _environment(tester);
      for (final width in [0.0, double.nan, double.infinity, 16385.0]) {
        await expectLater(
          _scope(chapter, environment, width: width),
          throwsA(
            isA<NovelReaderNativeLayoutInputException>().having(
              (e) => e.failure,
              'failure',
              NovelReaderNativeLayoutInputFailure.geometry,
            ),
          ),
        );
      }
      await expectLater(
        _scope(chapter, environment, maxSizes: 1),
        throwsA(
          isA<NovelReaderNativeLayoutInputException>().having(
            (e) => e.failure,
            'failure',
            NovelReaderNativeLayoutInputFailure.budget,
          ),
        ),
      );
      final opaque = await _environment(
        tester,
        style: TextStyle(foreground: Paint()..color = Colors.red),
      );
      await expectLater(
        _scope(chapter, opaque),
        throwsA(
          isA<NovelReaderNativeLayoutInputException>().having(
            (e) => e.failure,
            'failure',
            NovelReaderNativeLayoutInputFailure.opaquePaint,
          ),
        ),
      );
    },
  );

  testWidgets(
    'caller scaler retirement cannot publish a scope after cancellation',
    (tester) async {
      final chapter = await _chapter();
      final token = NovelReaderPaginationCancellationToken();
      final environment = await _environment(
        tester,
        scaler: _RetiringScaler(token),
      );
      await expectLater(
        _scope(chapter, environment, cancellation: token),
        throwsA(isA<NovelReaderPaginationException>()),
      );
    },
  );

  testWidgets(
    'prepared chapter, resolved font scope, native session and real viewport share one layout',
    (tester) async {
      final chapter = await _chapter('<p>abcdefgh</p>');
      final environment = await _environment(
        tester,
        preferences: NovelReaderPreferences.defaults().copyWith(
          fontSize: 10,
          lineHeight: 1,
          paragraphSpacing: 0,
        ),
      );
      final scope = await _scope(chapter, environment, width: 20, height: 10);
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      final session = scope.openSession(
        cache: cache,
        layoutId: 'request',
        limits: _limits,
      );
      final parent = NovelReaderPaginationCancellationToken();
      final anchor = chapter.anchors.segments.first.projection.baseAnchor;
      final controller = NovelReaderNativePagedController(
        session: session,
        anchors: chapter.anchors,
        parent: parent,
        paginationKey: scope.paginationKey,
        position: NovelReaderProgressSnapshot(
          novelId: 'novel',
          episodeId: 'episode',
          flowMode: NovelReaderFlowMode.pagedLtr,
          scrollOffset: 0,
          pageIndex: 0,
          anchorNodeId: anchor.nodeId,
          anchorTextOffset: 5,
          anchorFormatVersion: anchor.formatVersion,
          anchorTextIdentity: anchor.textIdentity,
          progressPercent: .6,
          isProgressPercentValid: true,
        ),
      );
      addTearDown(() {
        controller.close();
        parent.cancel();
        session.close();
        cache.close();
      });
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 20,
              height: 10,
              child: NovelReaderNativePagedViewport(
                controller: controller,
                ownerIdentity: cache,
                readingAuthorityIdentity: Object(),
                onPositionChanged: reports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(reports.single.paginationKey, scope.paginationKey);
      expect(reports.single.pageIndex, 2);
      expect(reports.single.anchor.textOffset, 5);
      expect(reports.single.hasUserNavigated, isFalse);
      expect(cache.layoutBuildCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      expect(cache.activeLeases, 0);
    },
  );
}

class _BranchScaler extends TextScaler {
  _BranchScaler(double ratio) : _ratio = [ratio];
  // Deliberately mutable behind the immutable scaler interface.
  final List<double> _ratio;
  double get ratio => _ratio.single;
  set ratio(double value) => _ratio[0] = value;
  @override
  double scale(double fontSize) => fontSize == 40 ? fontSize * ratio : fontSize;
  @override
  double get textScaleFactor => 1;
  @override
  bool operator ==(Object other) => other is _BranchScaler;
  @override
  int get hashCode => 1;
}

class _RetiringScaler extends TextScaler {
  const _RetiringScaler(this.token);
  final NovelReaderPaginationCancellationToken token;
  @override
  double scale(double fontSize) {
    token.cancel();
    return fontSize;
  }

  @override
  double get textScaleFactor => 1;
}
