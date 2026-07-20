import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

import '../test_support/novel_pagination_html_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const loader = NovelPaginationHtmlFixtureLoader();
  for (final sample in novelPaginationHtmlFixtures) {
    test(
      'real UTF-8 ${sample.title} fixture reaches the hybrid planner',
      () async {
        final message = loader.loadFirstPostMessage(sample);
        final episode = NovelEpisodeItem(
          episodeId: 'fixture-${sample.id}',
          novelId: 'fixture-novel',
          sourceTid: '6200',
          episodeTitle: sample.title,
          orderIndex: 0,
        );
        final chapter = await const DefaultNovelReaderHtmlPreparationService()
            .prepare(
              rawHtml: message,
              episode: episode,
              preferences: _preferences,
              theme: _theme,
              sourceId: episode.episodeId,
              threadId: episode.sourceTid,
              imageCacheOwnerId: episode.sourceTid,
            );
        final key = NovelReaderPaginationKey(
          episodeId: chapter.episodeId,
          contentHash: chapter.contentHash,
          viewportWidthPx: 320,
          viewportHeightPx: 600,
          typographySignature: 'phase6-fixture',
          themeSignature: chapter.themeSignature,
          imageDimensionRevision: chapter.imageDimensionRevision,
          rendererRevision: 3,
        );
        final plan = await DefaultNovelReaderHybridPaginationPlanner(
          measureAdapter: const _FixtureMeasureAdapter(),
          preferences: _preferences,
          theme: _theme,
          baseStyle: _baseStyle,
          validationPolicy: const NovelReaderPaginationValidationPolicy(
            interval: 10000,
          ),
        ).paginate(chapter, key);

        expect(message.trim(), isNotEmpty);
        expect(plan.pages, isNotEmpty);
        expect(plan.pages.every((page) => page.html.trim().isNotEmpty), isTrue);
        expect(plan.rendererValidationMismatchCount, 0);
        switch (sample.id) {
          case 'ruby':
            expect(
              plan.routeCounts[NovelReaderPaginationRoute.rubyInline],
              greaterThan(0),
            );
          case 'collapse_directory':
            expect(
              plan.routeCounts[NovelReaderPaginationRoute.collapseBlock],
              greaterThan(0),
            );
          case 'text_color_size':
            expect(
              plan.routeCounts[NovelReaderPaginationRoute.isolatedImage],
              greaterThan(0),
            );
          case 'background_color':
            expect(plan.atomCount, greaterThan(0));
        }
      },
    );
  }

  test(
    'table fixture stays intact and oversized rows use inner scrolling',
    () async {
      const html = '''
      <p>表格之前的正文</p>
      <table><tbody>
        <tr><th>列一</th><th>列二</th></tr>
        <tr><td>内容一</td><td>内容二</td></tr>
      </tbody></table>
      <p>表格之后的正文</p>
    ''';
      final chapter = await const DefaultNovelReaderHtmlPreparationService()
          .prepare(
            rawHtml: html,
            episode: _tableEpisode,
            preferences: _preferences,
            theme: _theme,
            sourceId: _tableEpisode.episodeId,
            threadId: _tableEpisode.sourceTid,
            imageCacheOwnerId: _tableEpisode.sourceTid,
          );
      final plan =
          await DefaultNovelReaderHybridPaginationPlanner(
            measureAdapter: const _FixtureMeasureAdapter(tableHeight: 900),
            preferences: _preferences,
            theme: _theme,
            baseStyle: _baseStyle,
          ).paginate(
            chapter,
            NovelReaderPaginationKey(
              episodeId: chapter.episodeId,
              contentHash: chapter.contentHash,
              viewportWidthPx: 320,
              viewportHeightPx: 600,
              typographySignature: 'phase6-table',
              themeSignature: chapter.themeSignature,
              imageDimensionRevision: chapter.imageDimensionRevision,
              rendererRevision: 3,
            ),
          );

      final tablePage = plan.pages.singleWhere(
        (page) => page.html.contains('<table'),
      );
      expect(plan.routeCounts[NovelReaderPaginationRoute.tableBlock], 1);
      expect(tablePage.requiresInnerScroll, isTrue);
      expect(tablePage.html, contains('<tr>'));
      expect(tablePage.html, contains('内容二'));
    },
  );
}

const _tableEpisode = NovelEpisodeItem(
  episodeId: 'phase6-table-episode',
  novelId: 'phase6-fixture-novel',
  sourceTid: '6201',
  episodeTitle: 'Phase 6 表格样本',
  orderIndex: 0,
);

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

final class _FixtureMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _FixtureMeasureAdapter({this.tableHeight = 120});

  final double tableHeight;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return NovelReaderPaginationMeasureResult(
      height: request.html.contains('<table') ? tableHeight : 120,
    );
  }
}
