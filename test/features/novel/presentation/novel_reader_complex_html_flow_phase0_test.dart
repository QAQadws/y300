import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_layout_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_legacy_markup_normalizer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_extractor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

import '../test_support/novel_phase0_api_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'flowable classification keeps the current whole-atom page baseline',
    () async {
      final html = File(
        novelComplexHtmlInvalidFontFixturePath,
      ).readAsStringSync();
      final baseline = await _paginate(
        html: html,
        episodeId: 'phase0-invalid-font',
        legacyMarkupNormalizer: const NoopNovelReaderLegacyMarkupNormalizer(),
      );
      final unsupportedFontAtoms = baseline.classified
          .where(
            (atom) =>
                atom.route == NovelReaderPaginationRoute.flowableComplexText &&
                atom.reason == NovelReaderPaginationRouteReason.unsupportedFont,
          )
          .toList(growable: false);

      expect(unsupportedFontAtoms, hasLength(2));
      expect(
        unsupportedFontAtoms.map((atom) => atom.layoutPolicy.measure),
        everyElement(NovelReaderPaginationMeasurePolicy.htmlRendererRange),
      );
      expect(
        unsupportedFontAtoms.map((atom) => atom.layoutPolicy.split),
        everyElement(NovelReaderPaginationSplitPolicy.domBoundaries),
      );
      expect(
        unsupportedFontAtoms.map((atom) => atom.atom.html),
        everyElement(contains('face="&amp;quot"')),
      );
      expect(baseline.plan.pageCount, 3);
      expect(baseline.plan.complexBlockCount, 2);
      expect(baseline.plan.measurementCount, 2);
      expect(baseline.plan.flowableComplexAtomCount, 2);
      expect(baseline.plan.atomicWidgetAtomCount, 0);
      expect(baseline.plan.dedicatedContentAtomCount, 0);
      expect(baseline.firstPageDuration, isNotNull);

      final firstPage = baseline.plan.pages[0];
      final secondPage = baseline.plan.pages[1];
      expect(firstPage.html, contains('喜歡的人和義妹'));
      expect(firstPage.html, isNot(contains('第一話（１）')));
      expect(secondPage.html, contains('第一話（１）'));
      expect(secondPage.html, isNot(contains('如果能轉世重生')));
      expect(firstPage.gapReason, NovelReaderPageGapReason.atomicWidget);
      expect(secondPage.gapReason, NovelReaderPageGapReason.atomicWidget);
      expect(_fullness(firstPage), lessThan(0.1));
      expect(_fullness(secondPage), lessThan(0.1));
      final routeCounts = _routeCounts(baseline.classified);
      final reasonCounts = _reasonCounts(baseline.classified);

      // Stable structural diagnostics only; no body HTML is emitted.
      // ignore: avoid_print
      print(
        'NOVEL_COMPLEX_HTML_PHASE0 pages=${baseline.plan.pageCount} '
        'unsupportedFontAtoms=${unsupportedFontAtoms.length} '
        'measurements=${baseline.plan.measurementCount} '
        'rendererValidations=${baseline.plan.rendererValidationCount} '
        'routes=$routeCounts reasons=$reasonCounts '
        'firstPageMicros=${baseline.firstPageDuration!.inMicroseconds} '
        'firstFullness=${_fullness(firstPage).toStringAsFixed(4)} '
        'secondFullness=${_fullness(secondPage).toStringAsFixed(4)}',
      );
    },
  );

  test(
    'sanitized JSON fixtures retain only required version=1 structure',
    () async {
      for (final path in <String>[
        novelComplexHtmlThread511960FixturePath,
        novelComplexHtmlThread565218FixturePath,
      ]) {
        final fixture = await NovelPhase0ApiFixture.load(path);
        final variables = fixture.variables;
        final detail = fixture.parseDetail();

        expect(fixture.root['Version'], '1');
        expect(fixture.root['Charset'], 'UTF-8');
        expect(fixture.metadata['sanitizedExcerpt'], isTrue);
        expect(fixture.metadata['requestVersion'], '1');
        expect(detail.posts, isNotEmpty);
        for (final sensitiveKey in <String>[
          'auth',
          'cookiepre',
          'formhash',
          'saltkey',
          'member_uid',
          'member_username',
        ]) {
          expect(variables, isNot(contains(sensitiveKey)));
        }
        expect(detail.posts.every((post) => post.authorId == '1'), isTrue);
      }
    },
  );

  test(
    'provided fixtures lock safe, ruby, image, table, and collapse routes',
    () async {
      final thread511960 = await NovelPhase0ApiFixture.load(
        novelComplexHtmlThread511960FixturePath,
      );
      final thread565218 = await NovelPhase0ApiFixture.load(
        novelComplexHtmlThread565218FixturePath,
      );
      final existingLongText = await NovelPhase0ApiFixture.load(
        novelPaginationDivParagraphFixturePath,
      );

      final blockRoutes = await _classifyPosts(thread511960);
      final normalizedRoutes = await _classifyPosts(thread565218);
      final existingRoutes = await _classifyPosts(existingLongText);

      // Stable structural diagnostics only; no body HTML is emitted.
      // ignore: avoid_print
      print(
        'NOVEL_COMPLEX_HTML_FIXTURES '
        'blocksRoutes=${_routeCounts(blockRoutes)} '
        'blocksReasons=${_reasonCounts(blockRoutes)} '
        'normalizedRoutes=${_routeCounts(normalizedRoutes)} '
        'normalizedReasons=${_reasonCounts(normalizedRoutes)} '
        'existingRoutes=${_routeCounts(existingRoutes)} '
        'existingReasons=${_reasonCounts(existingRoutes)}',
      );

      expect(_routeCounts(blockRoutes), <NovelReaderPaginationRoute, int>{
        NovelReaderPaginationRoute.isolatedImage: 1,
        NovelReaderPaginationRoute.safeText: 13,
        NovelReaderPaginationRoute.tableBlock: 1,
      });
      expect(
        _reasonCounts(blockRoutes),
        <NovelReaderPaginationRouteReason, int>{
          NovelReaderPaginationRouteReason.isolatedReadableImage: 1,
          NovelReaderPaginationRouteReason.safeTextSubset: 13,
          NovelReaderPaginationRouteReason.containsTable: 1,
        },
      );
      expect(_routeCounts(normalizedRoutes), <NovelReaderPaginationRoute, int>{
        NovelReaderPaginationRoute.safeText: 10,
        NovelReaderPaginationRoute.collapseBlock: 2,
      });
      expect(
        _reasonCounts(normalizedRoutes),
        <NovelReaderPaginationRouteReason, int>{
          NovelReaderPaginationRouteReason.safeTextSubset: 10,
          NovelReaderPaginationRouteReason.containsCollapse: 2,
        },
      );
      expect(_routeCounts(existingRoutes), <NovelReaderPaginationRoute, int>{
        NovelReaderPaginationRoute.safeText: 95,
        NovelReaderPaginationRoute.rubyInline: 2,
      });
      expect(
        _reasonCounts(existingRoutes),
        <NovelReaderPaginationRouteReason, int>{
          NovelReaderPaginationRouteReason.safeTextSubset: 95,
          NovelReaderPaginationRouteReason.containsRuby: 2,
        },
      );
    },
  );

  test(
    'phase 2 normalizes invalid font titles onto the safe text path',
    () async {
      final html = File(
        novelComplexHtmlInvalidFontFixturePath,
      ).readAsStringSync();
      final normalized = await _paginate(
        html: html,
        episodeId: 'phase2-normalized-font',
      );

      expect(normalized.chapter.legacyMarkupNormalization.revision, 1);
      expect(
        normalized.chapter.legacyMarkupNormalization.normalizedAttributeCount,
        2,
      );
      expect(normalized.chapter.html, isNot(contains('face=')));
      expect(
        normalized.classified,
        everyElement(
          isA<NovelReaderClassifiedPaginationAtom>().having(
            (atom) => atom.route,
            'route',
            NovelReaderPaginationRoute.safeText,
          ),
        ),
      );
      expect(normalized.plan.pageCount, 1);
      expect(normalized.plan.complexBlockCount, 0);
      expect(normalized.plan.measurementCount, 1);
      expect(normalized.plan.rendererValidationCount, 1);
      expect(normalized.plan.pages.first.html, contains('喜歡的人和義妹'));
      expect(normalized.plan.pages.first.html, contains('第一話（１）'));
      expect(normalized.plan.pages.first.html, contains('如果能轉世重生'));
    },
  );
}

Future<List<NovelReaderClassifiedPaginationAtom>> _classifyPosts(
  NovelPhase0ApiFixture fixture,
) async {
  final detail = fixture.parseDetail();
  final result = <NovelReaderClassifiedPaginationAtom>[];
  for (final post in detail.posts) {
    final chapter = await _prepare(
      html: post.message,
      episodeId: 'fixture-${detail.tid}-${post.pid}',
      sourceTid: detail.tid,
    );
    result.addAll(_classify(chapter));
  }
  return result;
}

Future<_Phase0Baseline> _paginate({
  required String html,
  required String episodeId,
  NovelReaderLegacyMarkupNormalizer legacyMarkupNormalizer =
      const DefaultNovelReaderLegacyMarkupNormalizer(),
}) async {
  final chapter = await _prepare(
    html: html,
    episodeId: episodeId,
    legacyMarkupNormalizer: legacyMarkupNormalizer,
  );
  final classified = _classify(chapter);
  final key = NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: 600,
    typographySignature: 'complex-html-phase0',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 12,
  );
  final planner = DefaultNovelReaderHybridPaginationPlanner(
    measureAdapter: const _Phase0MeasureAdapter(),
    preferences: _preferences,
    theme: _theme,
    baseStyle: _baseStyle,
  );
  final coordinator = DefaultNovelReaderPaginationCoordinator(
    pageBreaker: planner,
  );
  final stopwatch = Stopwatch()..start();
  Duration? firstPageDuration;
  NovelReaderPaginationPlan? finalPlan;
  await for (final progress in coordinator.paginateIncrementally(
    chapter: chapter,
    key: key,
  )) {
    if (firstPageDuration == null && progress.plan.pages.isNotEmpty) {
      firstPageDuration = stopwatch.elapsed;
    }
    finalPlan = progress.plan;
    if (progress.isComplete) {
      break;
    }
  }
  stopwatch.stop();
  return _Phase0Baseline(
    chapter: chapter,
    classified: classified,
    plan: finalPlan!,
    firstPageDuration: firstPageDuration,
  );
}

Future<NovelReaderPreparedChapter> _prepare({
  required String html,
  required String episodeId,
  String sourceTid = 'phase0-thread',
  NovelReaderLegacyMarkupNormalizer legacyMarkupNormalizer =
      const DefaultNovelReaderLegacyMarkupNormalizer(),
}) {
  final episode = NovelEpisodeItem(
    episodeId: episodeId,
    novelId: 'phase0-novel',
    sourceTid: sourceTid,
    episodeTitle: 'Phase 0 complex HTML baseline',
    orderIndex: 0,
  );
  return DefaultNovelReaderHtmlPreparationService(
    preparer: NovelHtmlChapterRenderPreparer(
      legacyMarkupNormalizer: legacyMarkupNormalizer,
    ),
  ).prepare(
    rawHtml: html,
    episode: episode,
    preferences: _preferences,
    theme: _theme,
    sourceId: episodeId,
    threadId: sourceTid,
    imageCacheOwnerId: sourceTid,
  );
}

List<NovelReaderClassifiedPaginationAtom> _classify(
  NovelReaderPreparedChapter chapter,
) {
  return const NovelReaderPaginationAtomExtractor()
      .extract(chapter)
      .map(
        (atom) => const NovelReaderPaginationAtomClassifier().classify(
          atom: atom,
          baseStyle: _baseStyle,
          preferences: _preferences,
          theme: _theme,
        ),
      )
      .toList(growable: false);
}

double _fullness(NovelReaderPageFragment page) {
  return page.availableHeight <= 0
      ? 0
      : (page.usedHeight / page.availableHeight).clamp(0, 1);
}

Map<NovelReaderPaginationRoute, int> _routeCounts(
  List<NovelReaderClassifiedPaginationAtom> classified,
) {
  final counts = <NovelReaderPaginationRoute, int>{};
  for (final atom in classified) {
    counts.update(atom.route, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<NovelReaderPaginationRouteReason, int> _reasonCounts(
  List<NovelReaderClassifiedPaginationAtom> classified,
) {
  final counts = <NovelReaderPaginationRouteReason, int>{};
  for (final atom in classified) {
    counts.update(atom.reason, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

final class _Phase0Baseline {
  const _Phase0Baseline({
    required this.chapter,
    required this.classified,
    required this.plan,
    required this.firstPageDuration,
  });

  final NovelReaderPreparedChapter chapter;
  final List<NovelReaderClassifiedPaginationAtom> classified;
  final NovelReaderPaginationPlan plan;
  final Duration? firstPageDuration;
}

final class _Phase0MeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _Phase0MeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return const NovelReaderPaginationMeasureResult(height: 30);
  }
}

const _preferences = ForumHtmlReaderPreferences(
  typography: RichTextTypography(
    fontScale: 18.5 / 14,
    lineHeightScale: 1.6,
    paragraphSpacing: 12,
  ),
  conversionMode: TextConversionMode.none,
);

const _baseStyle = TextStyle(
  color: Color(0xFF4C3A21),
  fontSize: 18.5,
  height: 1.6,
);

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);
