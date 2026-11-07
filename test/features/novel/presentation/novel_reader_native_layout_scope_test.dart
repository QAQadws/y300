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
import 'package:y300/features/novel/presentation/services/novel_reader_native_image_resources.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_render_environment.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';

import '../test_support/native_reader_image_test_host.dart';

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
  Color? quoteBackground,
  Color? quoteForeground,
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
              colorScheme: theme.colorScheme.copyWith(
                onSurface: foreground,
                surfaceContainerHighest: quoteBackground,
                onSurfaceVariant: quoteForeground,
              ),
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
  int? cacheEntries,
  int? cacheBytes,
  NovelReaderNativeImageCatalog? images,
}) => NovelReaderNativeLayoutScope.prepare(
  chapter: chapter,
  environment: environment,
  width: width,
  height: height,
  maxIssuedLeases: maxIssuedLeases,
  maxParagraphCacheEntries: cacheEntries,
  maxParagraphCacheEstimatedBytes: cacheBytes,
  cancellation: cancellation ?? NovelReaderPaginationCancellationToken(),
  maxScaledFontSizes: maxSizes,
  images: images,
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
  testWidgets('role sizing changes native rows and invalidates the old scope', (
    tester,
  ) async {
    final chapter = await _chapter(
      '<h2 style="font-size:20px;line-height:1;margin:0">abcdefgh</h2>'
      '<p style="margin:0">ab</p>',
    );
    final defaults = NovelReaderPreferences.defaults().copyWith(
      fontSize: 20,
      lineHeight: 1,
    );
    final initial = await _environment(tester, preferences: defaults);
    final adjusted = await _environment(
      tester,
      preferences: defaults.copyWith(
        typography: const NovelReaderTypographyOverrides(
          roleFontSizes: NovelReaderRoleFontSizes(heading: 150),
        ),
      ),
    );
    final base = await _scope(chapter, initial, width: 85, height: 240);
    final larger = await _scope(chapter, adjusted, width: 85, height: 240);
    expect(larger.chapter, same(base.chapter));
    expect(larger.paginationKey, isNot(base.paginationKey));
    expect(
      base.tryUpdateCanvas(
        environment: adjusted,
        width: base.width,
        height: base.height,
        fontCollectionGeneration: 0,
        isCurrent: () => true,
      ),
      isNull,
    );

    Map<String?, int> rows(
      NovelReaderNativeLayoutScope scope,
      ForumBodyTableExtent extent,
    ) {
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 22,
      );
      final session = scope.openSession(
        cache: cache,
        layoutId: extent.name,
        limits: _limits,
        tableExtent: extent,
      );
      try {
        final counts = <String?, int>{};
        for (var step = 0; !session.isComplete; step++) {
          expect(step, lessThan(1000));
          session.advance(maxEvents: 4, maxLines: 1);
        }
        for (final page in session.snapshot) {
          for (final part in page.fragments) {
            counts[part.path] =
                (counts[part.path] ?? 0) + part.endLine - part.startLine;
          }
        }
        return counts;
      } finally {
        session.close();
        cache.close();
      }
    }

    for (final extent in ForumBodyTableExtent.values) {
      expect(rows(base, extent), {'0': 2, '1': 1});
      expect(rows(larger, extent), {'0': 4, '1': 1});
    }
  });

  testWidgets(
    'image geometry enters the layout key independently of font and IR',
    (tester) async {
      final chapter = await _chapter('<img src="https://x/a.png">');
      final host = NativeReaderImageTestHost();
      final resources = NovelReaderNativeImageResources(
        chapter: chapter,
        host: host,
        policy: host,
      );
      final scheduler = NovelReaderNativeWorkScheduler(nextFrame: () async {});
      final environment = await _environment(tester);
      final before = await resources.capture(
        reader: environment.reader,
        cancellation: NovelReaderPaginationCancellationToken(),
        maxCodeUnits: 10000,
        scheduler: scheduler,
      );
      final after = await resources.capture(
        reader: environment.reader,
        cancellation: NovelReaderPaginationCancellationToken(),
        maxCodeUnits: 10000,
        resolvedLayouts: {'0': const ForumHtmlImageLayout(aspectRatio: 4)},
        scheduler: scheduler,
      );
      final first = await _scope(chapter, environment, images: before);
      final next = await _scope(chapter, environment, images: after);
      expect(next.paginationKey, isNot(first.paginationKey));
      expect(next.chapter, same(first.chapter));
      expect(next.reader.fontRevision, first.reader.fontRevision);
      final canvas = next.tryUpdateCanvas(
        environment: environment,
        width: 200,
        height: 200,
        fontCollectionGeneration: 0,
        isCurrent: () => true,
      )!;
      expect(canvas.images, same(after));
      expect(canvas.paginationKey, next.paginationKey);
    },
  );

  testWidgets(
    'floated image uses the frozen natural width in both reading modes',
    (tester) async {
      final chapter = await _chapter(
        '<img src="https://x/a.png" style="float:left;margin-right:4px">AB',
      );
      final host = NativeReaderImageTestHost();
      final resources = NovelReaderNativeImageResources(
        chapter: chapter,
        host: host,
        policy: host,
      );
      final environment = await _environment(tester);
      final keys = <String>{};
      for (final width in [24.0, 48.0]) {
        final images = await resources.capture(
          reader: environment.reader,
          cancellation: NovelReaderPaginationCancellationToken(),
          maxCodeUnits: 10000,
          resolvedLayouts: {
            chapter.document.imageElements.single.path: ForumHtmlImageLayout(
              aspectRatio: 2,
              displaySize: Size(width, width / 2),
            ),
          },
          scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
        );
        final scope = await _scope(chapter, environment, images: images);
        expect(keys.add(scope.paginationKey), isTrue);
        for (final extent in ForumBodyTableExtent.values) {
          final cache = ForumBodyParagraphCache(
            maxEntries: 8,
            maxEstimatedBytes: 1 << 22,
          );
          final session = scope.openSession(
            cache: cache,
            layoutId: 'float-image-${extent.name}',
            limits: _limits,
            tableExtent: extent,
          );
          try {
            for (var step = 0; !session.isComplete; step++) {
              expect(step, lessThan(1000));
              session.advance(maxEvents: 4, maxLines: 1);
            }
            final parts = session.snapshot.single.fragments;
            expect(parts.first.isFloated, isTrue);
            expect(
              parts.first.imageFrame!.imageRect.size,
              Size(width, width / 2),
            );
            expect(parts.last.left, width + 4);
          } finally {
            session.close();
            cache.close();
          }
        }
      }
    },
  );

  testWidgets(
    'script displacement captures a parent font with no visible glyph run',
    (tester) async {
      final chapter = await _chapter(
        '<p>A<span style="font-size:40px">'
        '<sup style="font-size:12px">2</sup></span>B</p>',
      );
      final ordinary = await _scope(chapter, await _environment(tester));
      final scaled = await _scope(
        chapter,
        await _environment(tester, scaler: _BranchScaler(1.5)),
      );
      expect(scaled.paginationKey, isNot(ordinary.paginationKey));
      expect(scaled.textScaler.scale(40), 60);
      for (final scope in [ordinary, scaled]) {
        final cache = ForumBodyParagraphCache(
          maxEntries: 8,
          maxEstimatedBytes: 1 << 22,
        );
        final session = scope.openSession(
          cache: cache,
          layoutId: 'script-parent',
          limits: _limits,
        );
        try {
          for (var i = 0; !session.isComplete; i++) {
            expect(i, lessThan(1000));
            session.advance(maxEvents: 4, maxLines: 1);
          }
          final job = session.openPagePreparation(0);
          try {
            while (!job.isReady) {
              job.advance(maxFragments: 1, maxParts: 1);
            }
            final fragments = job.takeFragments();
            try {
              final binding =
                  fragments.single as ForumBodyPreparedInlineFragment;
              final context = binding.view.content.contexts.singleWhere(
                (c) => c.content.projection.text == '2',
              );
              final shift = context.content.style.baselineShift.resolve(
                scope.textScaler,
              );
              expect(shift, identical(scope, scaled) ? 24 : 16);
              final box = binding
                  .glyphBoxes(context.startUtf16, context.endUtf16)
                  .single;
              expect(box.top, greaterThanOrEqualTo(-1e-3));
              expect(
                box.bottom,
                lessThanOrEqualTo(
                  session.snapshot.single.fragments.single.height + 1e-3,
                ),
              );
            } finally {
              for (final f in fragments) {
                f.close();
              }
            }
          } finally {
            job.close();
          }
        } finally {
          session.close();
          cache.close();
        }
        expect(cache.activeLeases, 0);
      }
    },
  );

  testWidgets(
    'quote theme colors are frozen and invalidate native content without conflating the page canvas',
    (tester) async {
      final chapter = await _chapter(
        '<div class="quote"><blockquote><p>quoted</p></blockquote></div>',
      );
      final base = await _scope(chapter, await _environment(tester));
      for (final environment in [
        await _environment(tester, quoteBackground: Colors.green),
        await _environment(tester, quoteForeground: Colors.red),
      ]) {
        final changed = await _scope(chapter, environment);
        expect(changed.paginationKey, isNot(base.paginationKey));
        expect(
          base.tryUpdateCanvas(
            environment: environment,
            width: base.width,
            height: base.height,
            fontCollectionGeneration: 0,
            isCurrent: () => true,
          ),
          isNull,
        );
      }
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 22,
      );
      final session = base.openSession(
        cache: cache,
        layoutId: 'quote',
        limits: _limits,
      );
      try {
        while (!session.isComplete) {
          session.advance(maxEvents: 8, maxLines: 4);
        }
        final box = session.snapshot.single.backgrounds.single;
        expect(box.color, base.reader.theme!.quoteSurface);
        expect(box.quoteDecoration!.borderColor, base.reader.linkColor);
        final leases = session.preparePageLeases(0);
        expect(
          leases.single.content.style.textStyle.color,
          base.reader.theme!.quoteForeground,
        );
        for (final lease in leases) {
          lease.release();
        }
      } finally {
        session.close();
        cache.close();
      }
    },
  );
  testWidgets(
    'ignored emphasis does not add a font scale to the reading layout',
    (tester) async {
      final chapter = await _chapter(
        '<p style="margin:0;font-size:80px;text-emphasis:\'X\' red">AB</p>',
      );
      final scaler = _BranchScaler(1.6);
      final environment = await _environment(tester, scaler: scaler);
      final first = await _scope(chapter, environment, width: 400, height: 400);
      expect(first.textScaler.scale(80), 80);
      expect(first.textScaler.sizes, isNot(contains(40.0)));
      scaler.ratio = 2;
      final second = await _scope(
        chapter,
        environment,
        width: 400,
        height: 400,
      );
      expect(second.textScaler.scale(80), 80);
      expect(second.textScaler.sizes, first.textScaler.sizes);
      expect(first.paginationKey, second.paginationKey);
      expect(
        first.tryUpdateCanvas(
          environment: environment,
          width: 400,
          height: 400,
          fontCollectionGeneration: 0,
          isCurrent: () => true,
        ),
        isNotNull,
      );
      expect(
        (await _scope(chapter, environment, maxSizes: 2)).textScaler.sizes,
        first.textScaler.sizes,
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 32,
        maxEstimatedBytes: 1 << 24,
      );
      final session = first.openSession(
        cache: cache,
        layoutId: 'emphasis',
        limits: _limits,
      );
      addTearDown(() {
        session.close();
        cache.close();
      });
      for (var n = 0; !session.isComplete; n++) {
        if (n > 10000) fail('Reading session did not finish');
        final step = session.advance(
          maxEvents: 2,
          maxLines: 1,
          maxFormatParts: 1,
        );
        expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
        expect(step.layoutsBuilt, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
      }
      final preparation = session.openPagePreparation(0);
      while (!preparation.isReady) {
        preparation.advance(maxFragments: 1, maxParts: 1);
      }
      final binding =
          preparation.takeFragments().single
              as ForumBodyPreparedParagraphFragment;
      preparation.close();
      expect(binding.lease.content.runs.single.style.textStyle.fontSize, 80);
      expect(binding.projection.text, 'AB');
      expect(binding.glyphBoxes(0, 1), isNotEmpty);
      session.close();
      expect(binding.isActive, isFalse);
      expect(cache.activeLeases, 0);
    },
  );

  testWidgets(
    'actual cache byte capacity limits and identifies both visible pages',
    (tester) async {
      final chapter = await _chapter();
      final environment = await _environment(tester);
      final first = await _scope(
        chapter,
        environment,
        cacheBytes: 16 * 1024 * 1024,
      );
      final smaller = await _scope(
        chapter,
        environment,
        cacheBytes: 8 * 1024 * 1024,
      );
      final same = await _scope(
        chapter,
        environment,
        cacheBytes: 16 * 1024 * 1024,
      );
      expect(first.paginationKey, same.paginationKey);
      expect(first.paginationKey, isNot(smaller.paginationKey));
      expect(
        first.maxNativeEstimatedBytesPerPage! * 2 +
            2 * ForumBodyParagraphCache.sourceFreeFontEstimatedBytes,
        16 * 1024 * 1024,
      );
      expect(
        smaller.maxNativeEstimatedBytesPerPage,
        lessThan(first.maxNativeEstimatedBytesPerPage!),
      );
      expect(
        first
            .tryUpdateCanvas(
              environment: environment,
              width: 200,
              height: 200,
              fontCollectionGeneration: 0,
              isCurrent: () => true,
            )!
            .maxNativeEstimatedBytesPerPage,
        first.maxNativeEstimatedBytesPerPage,
      );
      await expectLater(
        _scope(chapter, environment, cacheBytes: 0),
        throwsArgumentError,
      );
    },
  );
  testWidgets('actual cache entry capacity participates in layout identity', (
    tester,
  ) async {
    final chapter = await _chapter();
    final environment = await _environment(tester);
    final a = await _scope(chapter, environment, cacheEntries: 64);
    final b = await _scope(chapter, environment, cacheEntries: 32);
    final same = await _scope(chapter, environment, cacheEntries: 64);
    expect(a.maxNativeEntriesPerPage, 31);
    expect(b.maxNativeEntriesPerPage, 15);
    expect(a.paginationKey, isNot(b.paginationKey));
    expect(a.paginationKey, same.paginationKey);
    expect(a.maxNativeHandlesPerPage, b.maxNativeHandlesPerPage);
    await expectLater(
      _scope(chapter, environment, cacheEntries: 0),
      throwsArgumentError,
    );
  });

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
      final equivalentAlignment = await _scope(
        chapter,
        await _environment(
          tester,
          preferences: NovelReaderPreferences.defaults().copyWith(
            typography: const NovelReaderTypographyOverrides(
              textAlignment: NovelReaderTextAlignment(
                mode: NovelReaderTextAlignMode.start,
                scope: NovelReaderStyleScope.asDefault,
              ),
            ),
          ),
        ),
      );
      expect(equivalentAlignment.paginationKey, base.paginationKey);
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
        for (final mode in NovelReaderTextAlignMode.values)
          NovelReaderPreferences.defaults().copyWith(
            typography: NovelReaderTypographyOverrides(
              textAlignment: NovelReaderTextAlignment(mode: mode),
            ),
          ),
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
    'canvas colors preserve paragraph identity and full paint precision',
    (tester) async {
      final chapter = await _chapter();
      final base = await _scope(chapter, await _environment(tester));
      const colors = [
        Colors.green,
        Colors.blue,
        Color.from(alpha: 1, red: .5001, green: .2, blue: .3),
        Color.from(alpha: 1, red: .5002, green: .2, blue: .3),
      ];
      for (final color in colors) {
        final environment = await _environment(tester, background: color);
        final scope = await _scope(chapter, environment);
        expect(scope.paginationKey, base.paginationKey);
        expect(
          scope.backgroundColor,
          Color.from(
            alpha: color.a,
            red: color.r,
            green: color.g,
            blue: color.b,
            colorSpace: color.colorSpace,
          ),
        );
        expect(scope.reader.textStyle, base.reader.textStyle);
        final canvas = base.tryUpdateCanvas(
          environment: environment,
          width: base.width,
          height: base.height,
          fontCollectionGeneration: 0,
          isCurrent: () => true,
        )!;
        expect(canvas.paginationKey, base.paginationKey);
        expect(canvas.reader, same(base.reader));
        expect(canvas.textScaler, same(base.textScaler));
        expect(canvas.backgroundColor, scope.backgroundColor);
      }
      final inlineBackground = await _scope(
        chapter,
        await _environment(
          tester,
          style: const TextStyle(
            fontFamily: 'Ahem',
            letterSpacing: 0,
            wordSpacing: 0,
            backgroundColor: Colors.green,
          ),
        ),
      );
      expect(inlineBackground.paginationKey, isNot(base.paginationKey));
      final textColor = await _scope(
        chapter,
        await _environment(tester, foreground: Colors.green),
      );
      expect(textColor.paginationKey, isNot(base.paginationKey));
    },
  );
  testWidgets(
    'canvas check rejects different inputs, nonlinear samples and retirement',
    (tester) async {
      final chapter = await _chapter();
      final scaler = _BranchScaler(1);
      final base = await _scope(
        chapter,
        await _environment(tester, scaler: scaler),
      );
      NovelReaderNativeLayoutScope? update(
        NovelReaderNativeRenderEnvironment environment, {
        double? width,
        double? height,
        int generation = 0,
        bool Function()? current,
      }) => base.tryUpdateCanvas(
        environment: environment,
        width: width ?? base.width,
        height: height ?? base.height,
        fontCollectionGeneration: generation,
        isCurrent: current ?? () => true,
      );
      final canvas = await _environment(
        tester,
        scaler: scaler,
        background: Colors.blue,
      );
      expect(update(canvas), isNotNull);
      expect(update(canvas, width: base.width + 1), isNull);
      expect(update(canvas, height: base.height + 1), isNull);
      expect(update(canvas, generation: 1), isNull);
      expect(update(canvas, current: () => false), isNull);
      for (final candidate in [
        await _environment(tester, scaler: scaler, foreground: Colors.red),
        await _environment(
          tester,
          scaler: scaler,
          direction: TextDirection.rtl,
        ),
        await _environment(tester, scaler: scaler, locale: const Locale('ja')),
        await _environment(
          tester,
          scaler: scaler,
          preferences: NovelReaderPreferences.defaults().copyWith(fontSize: 25),
        ),
        await _environment(
          tester,
          scaler: scaler,
          policy: ForumBodyStylePolicy({
            ForumBodyStyleProperty.foreground: ForumBodyStyleScope.forceAll,
          }),
        ),
      ]) {
        expect(update(candidate), isNull);
      }
      scaler.ratio = 2;
      expect(
        update(canvas),
        isNull,
        reason: 'Same scaler object/root factor, changed author size40',
      );
      scaler.ratio = double.nan;
      expect(update(canvas), isNull);
      scaler.ratio = 1;
      final token = NovelReaderPaginationCancellationToken();
      final retiring = await _environment(
        tester,
        scaler: _RetiringScaler(token),
      );
      expect(update(retiring, current: () => !token.isCancelled), isNull);
      expect(token.isCancelled, true);
      final opaque = await _environment(
        tester,
        style: TextStyle(background: Paint()),
      );
      expect(
        () => update(opaque),
        throwsA(isA<NovelReaderNativeLayoutInputException>()),
      );
    },
  );
  testWidgets(
    'non-finite canvas values fail both full and paint-only admission',
    (tester) async {
      final chapter = await _chapter();
      final base = await _scope(chapter, await _environment(tester));
      for (final color in [
        const Color.from(alpha: double.nan, red: 0, green: 0, blue: 0),
        const Color.from(alpha: 1, red: double.infinity, green: 0, blue: 0),
      ]) {
        final environment = await _environment(tester, background: color);
        final failure = isA<NovelReaderNativeLayoutInputException>().having(
          (e) => e.failure,
          'failure',
          NovelReaderNativeLayoutInputFailure.opaquePaint,
        );
        await expectLater(_scope(chapter, environment), throwsA(failure));
        expect(
          () => base.tryUpdateCanvas(
            environment: environment,
            width: base.width,
            height: base.height,
            fontCollectionGeneration: 0,
            isCurrent: () => true,
          ),
          throwsA(failure),
        );
      }
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

  for (final format in ['ordinary', 'ignored-emphasis', 'status']) {
    final emphasis = format == 'ignored-emphasis', fitted = format == 'status';
    testWidgets(
      'prepared chapter, resolved font scope and real viewport share one layout ($format)',
      (tester) async {
        final chapter = await _chapter(
          '${fitted ? '<div class="pstatus" style="margin:0;text-emphasis:\'X\' red">statusABCDEFGHIJ</div>' : ''}'
          '<p style="margin:0;${emphasis ? 'text-emphasis:\'X\' red' : ''}">abcdefgh</p>',
        );
        final environment = await _environment(
          tester,
          preferences: NovelReaderPreferences.defaults().copyWith(
            fontSize: 10,
            lineHeight: 1,
            paragraphSpacing: 0,
          ),
        );
        final pageHeight = fitted ? 20.0 : 10.0;
        final scope = await _scope(
          chapter,
          environment,
          width: 20,
          height: pageHeight,
        );
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
                height: pageHeight,
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
        expect(reports.single.pageIndex, fitted ? 0 : 2);
        expect(reports.single.anchor.textOffset, 5);
        expect(reports.single.hasUserNavigated, isFalse);
        if (emphasis || fitted) {
          expect(find.byType(ForumBodyParagraphSurface), findsWidgets);
          expect(controller.requestPage(fitted ? 1 : 3), isTrue);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(reports.last.pageIndex, fitted ? 1 : 3);
          expect(reports.last.hasUserNavigated, isTrue);
        } else {
          expect(cache.layoutBuildCount, 1);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.close();
        expect(cache.activeLeases, 0);
      },
    );
  }
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
