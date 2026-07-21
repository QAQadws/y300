import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_classifier.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_extractor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

import '../test_support/novel_phase0_api_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'user version=1 fixture reports safe-text coverage and page fill',
    () async {
      final result = await _paginateFixture(
        novelPaginationShortParagraphFixturePath,
        episodeTitle: '第二章 白玉手串',
      );

      _printDiagnostic('short-paragraph', result);
      expect(result.fixture.root['Version'], '1');
      expect(result.fixture.variables, isNot(contains('auth')));
      expect(result.fixture.variables, isNot(contains('formhash')));
      expect(result.postPid, '41569751');
      expect(result.message, contains('第二章　白玉手串'));
      expect(result.report.totalTextCharacters, greaterThan(30000));
      expect(
        result.atoms.where(
          (atom) => atom.html.startsWith(RegExp(r'[\t\n\f\r ]')),
        ),
        isEmpty,
      );
      expect(result.report.safeAtomRate, 1);
      expect(result.report.safeTextCharacterRate, 1);
      expect(result.report.routeCounts.keys, <NovelReaderPaginationRoute>{
        NovelReaderPaginationRoute.safeText,
      });
      expect(result.plan.pageCount, inInclusiveRange(120, 150));
      expect(result.plan.pageCount, lessThan(1127));
      expect(result.plan.averageTextPageFullness, greaterThan(0.85));
      expect(result.plan.complexBlockCount, 0);
      expect(result.plan.rendererValidationCount, lessThan(20));
    },
  );

  test('div paragraph fixture reports production pagination routing', () async {
    final result = await _paginateFixture(
      novelPaginationDivParagraphFixturePath,
      episodeTitle: 'ACT01',
    );

    _printDiagnostic('div-paragraph', result);
    expect(result.fixture.root['Version'], '1');
    expect(result.fixture.variables, isNot(contains('auth')));
    expect(result.fixture.variables, isNot(contains('formhash')));
    expect(result.postPid, '41425060');
    expect(result.message, contains('ACT01'));
    expect(result.message.length, greaterThan(8000));
    expect(result.report.totalTextCharacters, greaterThan(1500));
    expect(result.report.safeAtomRate, greaterThan(0.97));
    expect(result.report.safeTextCharacterRate, greaterThan(0.95));
    expect(result.report.routeCounts, <NovelReaderPaginationRoute, int>{
      NovelReaderPaginationRoute.safeText: 95,
      NovelReaderPaginationRoute.rubyInline: 2,
    });
    expect(result.plan.pageCount, inInclusiveRange(7, 15));
    expect(result.plan.pageCount, lessThan(96));
    expect(result.plan.averageTextPageFullness, greaterThan(0.8));
    expect(result.plan.complexBlockCount, 2);
    expect(result.plan.rendererValidationCount, lessThan(10));
  });
}

Future<_FixturePaginationResult> _paginateFixture(
  String path, {
  required String episodeTitle,
}) async {
  final fixture = await NovelPhase0ApiFixture.load(path);
  final detail = fixture.parseDetail();
  final post = detail.posts.single;
  final episode = NovelEpisodeItem(
    episodeId: 'fixture-${post.pid}',
    novelId: 'fixture-novel-${detail.tid}',
    sourceTid: detail.tid,
    sourcePid: post.pid,
    episodeTitle: episodeTitle,
    orderIndex: 0,
  );
  final chapter = await const DefaultNovelReaderHtmlPreparationService()
      .prepare(
        rawHtml: post.message,
        episode: episode,
        preferences: _preferences,
        theme: _theme,
        sourceId: episode.episodeId,
        threadId: detail.tid,
        imageCacheOwnerId: detail.tid,
      );
  final atoms = const NovelReaderPaginationAtomExtractor().extract(chapter);
  final classified = atoms
      .map(
        (atom) => const NovelReaderPaginationAtomClassifier().classify(
          atom: atom,
          baseStyle: _baseStyle,
          preferences: _preferences,
          theme: _theme,
        ),
      )
      .toList(growable: false);
  final report = _coverage(classified);
  final key = NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: 600,
    typographySignature: 'fixture-default',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 9,
  );
  final plan = await DefaultNovelReaderHybridPaginationPlanner(
    measureAdapter: const _FixtureMeasureAdapter(),
    preferences: _preferences,
    theme: _theme,
    baseStyle: _baseStyle,
  ).paginate(chapter, key);
  return _FixturePaginationResult(
    fixture: fixture,
    postPid: post.pid,
    message: post.message,
    atoms: atoms,
    report: report,
    plan: plan,
  );
}

void _printDiagnostic(String label, _FixturePaginationResult result) {
  final report = result.report;
  final plan = result.plan;
  // Kept deliberately visible in CI output so fixture changes report both
  // routing and user-facing page-density regressions.
  // ignore: avoid_print
  print(
    'NOVEL_PAGINATION_FIXTURE label=$label '
    'atoms=${report.totalAtoms} safeAtoms=${report.safeAtoms} '
    'safeAtomRate=${report.safeAtomRate.toStringAsFixed(4)} '
    'textChars=${report.totalTextCharacters} '
    'safeTextChars=${report.safeTextCharacters} '
    'safeTextCharacterRate=${report.safeTextCharacterRate.toStringAsFixed(4)} '
    'routes=${report.routeCounts} reasons=${report.reasonCounts} '
    'pages=${plan.pageCount} '
    'averageFullness=${plan.averageTextPageFullness.toStringAsFixed(4)} '
    'complexBlocks=${plan.complexBlockCount} '
    'rendererValidations=${plan.rendererValidationCount}',
  );
}

final class _FixturePaginationResult {
  const _FixturePaginationResult({
    required this.fixture,
    required this.postPid,
    required this.message,
    required this.atoms,
    required this.report,
    required this.plan,
  });

  final NovelPhase0ApiFixture fixture;
  final String postPid;
  final String message;
  final List<NovelReaderPaginationAtom> atoms;
  final _SafeTextCoverage report;
  final NovelReaderPaginationPlan plan;
}

_SafeTextCoverage _coverage(List<NovelReaderClassifiedPaginationAtom> atoms) {
  var safeAtoms = 0;
  var totalTextCharacters = 0;
  var safeTextCharacters = 0;
  final routeCounts = <NovelReaderPaginationRoute, int>{};
  final reasonCounts = <NovelReaderPaginationRouteReason, int>{};
  for (final atom in atoms) {
    routeCounts.update(atom.route, (value) => value + 1, ifAbsent: () => 1);
    reasonCounts.update(atom.reason, (value) => value + 1, ifAbsent: () => 1);
    totalTextCharacters += atom.atom.textLength;
    if (atom.route == NovelReaderPaginationRoute.safeText) {
      safeAtoms += 1;
      safeTextCharacters += atom.atom.textLength;
    }
  }
  return _SafeTextCoverage(
    totalAtoms: atoms.length,
    safeAtoms: safeAtoms,
    totalTextCharacters: totalTextCharacters,
    safeTextCharacters: safeTextCharacters,
    routeCounts: routeCounts,
    reasonCounts: reasonCounts,
  );
}

final class _SafeTextCoverage {
  const _SafeTextCoverage({
    required this.totalAtoms,
    required this.safeAtoms,
    required this.totalTextCharacters,
    required this.safeTextCharacters,
    required this.routeCounts,
    required this.reasonCounts,
  });

  final int totalAtoms;
  final int safeAtoms;
  final int totalTextCharacters;
  final int safeTextCharacters;
  final Map<NovelReaderPaginationRoute, int> routeCounts;
  final Map<NovelReaderPaginationRouteReason, int> reasonCounts;

  double get safeAtomRate => totalAtoms == 0 ? 0 : safeAtoms / totalAtoms;

  double get safeTextCharacterRate =>
      totalTextCharacters == 0 ? 0 : safeTextCharacters / totalTextCharacters;
}

final class _FixtureMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _FixtureMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return const NovelReaderPaginationMeasureResult(height: 40);
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
