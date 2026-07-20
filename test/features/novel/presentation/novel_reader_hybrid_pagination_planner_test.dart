import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_hybrid_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_renderer_validator.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  test('pure text uses TextPainter with bounded HTML validation', () async {
    final chapter = await _prepare(
      '<p>${List<String>.filled(60, '混合分页正文 mixed 123。').join()}</p>',
    );
    final adapter = _RecordingMeasureAdapter();

    final plan = await _planner(
      adapter,
    ).paginate(chapter, _key(chapter, height: 120));

    expect(plan.pageCount, greaterThan(2));
    expect(plan.textFastPathCount, plan.pageCount);
    expect(plan.textLayoutCount, 1);
    expect(plan.complexBlockCount, 0);
    expect(plan.safeTextFallbackCount, 0);
    expect(plan.rendererValidationCount, greaterThan(0));
    expect(plan.rendererValidationCount, lessThan(plan.pageCount));
    expect(plan.measurementCount, plan.rendererValidationCount);
    expect(plan.domSliceCount, plan.pageCount);
    expect(plan.routeCounts[NovelReaderPaginationRoute.safeText], 1);
    expect(
      plan.pages
          .map((page) => html_parser.parseFragment(page.html).text ?? '')
          .join(),
      html_parser.parseFragment(chapter.html).text,
    );
  });

  test(
    'routes text, ruby, tables and readable images through one planner',
    () async {
      final chapter = await _prepare(
        '<p>普通正文</p>'
        '<p>前<ruby>字<rt>じ</rt></ruby>后</p>'
        '<table><tr><td>表格正文</td></tr></table>'
        '<img src="data/attachment/forum/phase4.jpg">',
      );
      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 160));

      expect(plan.routeCounts[NovelReaderPaginationRoute.safeText], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.rubyInline], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.tableBlock], 1);
      expect(plan.routeCounts[NovelReaderPaginationRoute.isolatedImage], 1);
      expect(plan.complexBlockCount, 2);
      expect(plan.readableImageCount, 1);
      expect(
        plan.pages.where((page) => page.containsIsolatedImage),
        hasLength(1),
      );
      expect(plan.pages.expand((page) => page.imageIndices), contains(0));
      expect(plan.pages.any((page) => page.html.contains('<ruby>')), isTrue);
      expect(plan.pages.any((page) => page.html.contains('<table>')), isTrue);
    },
  );

  test(
    'backs off to fewer complete lines after a validation mismatch',
    () async {
      final chapter = await _prepare(
        '<p>${List<String>.filled(20, '需要回退的安全正文。').join()}</p>',
      );
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, validationCall) {
          if (request.atomId?.endsWith(':validation') == true &&
              validationCall == 1) {
            return 240;
          }
          return 40;
        },
      );

      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.rendererValidationMismatchCount, 1);
      expect(plan.safeTextFallbackCount, 0);
      expect(plan.textFastPathCount, greaterThan(0));
      expect(plan.pages.every((page) => !page.requiresInnerScroll), isTrue);
    },
  );

  test(
    'falls back to a complex atom when bounded backoff still mismatches',
    () async {
      final chapter = await _prepare(
        '<p>${List<String>.filled(20, '持续不一致的正文。').join()}</p>',
      );
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, validationCall) {
          if (request.atomId?.endsWith(':validation') == true) {
            return 260;
          }
          return 80;
        },
      );

      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.rendererValidationMismatchCount, 2);
      expect(plan.safeTextFallbackCount, 1);
      expect(plan.complexBlockCount, 1);
      expect(plan.pageCount, 1);
      expect(plan.pages.single.html, chapter.html);
    },
  );

  test(
    'uses first-page remaining height to compose adjacent text atoms',
    () async {
      final chapter = await _prepare('<p>第一段短文。</p><p>第二段短文。</p>');
      final plan = await _planner(
        _RecordingMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 120));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.html, contains('第一段短文'));
      expect(plan.pages.single.html, contains('第二段短文'));
      expect(plan.pages.single.anchorRanges, hasLength(2));
    },
  );

  test(
    'marks oversized tables as inner-scroll pages without splitting rows',
    () async {
      const table = '<table><tr><td>第一行</td></tr><tr><td>第二行</td></tr></table>';
      final chapter = await _prepare(table);
      final adapter = _RecordingMeasureAdapter(
        heightFor: (request, _) => request.html.contains('<table>') ? 300 : 10,
      );
      final plan = await _planner(
        adapter,
      ).paginate(chapter, _key(chapter, height: 100));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.requiresInnerScroll, isTrue);
      expect(
        html_parser
            .parseFragment(plan.pages.single.html)
            .querySelectorAll('tr'),
        hasLength(2),
      );
    },
  );

  test('honors cancellation before publishing a plan', () async {
    final chapter = await _prepare('<p>正文</p>');
    final token = NovelReaderPaginationCancellationToken()..cancel();

    await expectLater(
      _planner(_RecordingMeasureAdapter()).plan(
        chapter: chapter,
        key: _key(chapter, height: 120),
        cancellationToken: token,
      ),
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'paginationCancelled',
        ),
      ),
    );
  });
}

DefaultNovelReaderHybridPaginationPlanner _planner(
  NovelReaderPaginationMeasureAdapter adapter,
) {
  return DefaultNovelReaderHybridPaginationPlanner(
    measureAdapter: adapter,
    preferences: _preferences,
    theme: _theme,
    baseStyle: _baseStyle,
    validationPolicy: const NovelReaderPaginationValidationPolicy(interval: 8),
  );
}

Future<NovelReaderPreparedChapter> _prepare(String html) {
  const episode = NovelEpisodeItem(
    episodeId: 'hybrid-episode',
    novelId: 'hybrid-novel',
    sourceTid: '100',
    episodeTitle: '混合分页',
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: html,
    episode: episode,
    preferences: _preferences,
    theme: _theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
  );
}

NovelReaderPaginationKey _key(
  NovelReaderPreparedChapter chapter, {
  required int height,
}) {
  return NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: height,
    typographySignature: 'font=18.5|line=1.6|hybrid',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 3,
  );
}

typedef _HeightFor =
    double Function(
      NovelReaderPaginationMeasureRequest request,
      int validationCall,
    );

final class _RecordingMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  _RecordingMeasureAdapter({this.heightFor});

  final _HeightFor? heightFor;
  int calls = 0;
  int validationCalls = 0;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    calls += 1;
    if (request.atomId?.endsWith(':validation') == true) {
      validationCalls += 1;
    }
    return NovelReaderPaginationMeasureResult(
      height: heightFor?.call(request, validationCalls) ?? 10,
    );
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
