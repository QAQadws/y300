import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  test(
    'splits long HTML text into valid fragments with stable anchors',
    () async {
      final longBody = List<String>.filled(80, '长正文').join();
      final chapter = await _prepare('<p>$longBody</p>');
      final plan = await NovelReaderHtmlPageBreaker(
        measureAdapter: const _TextHeightMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 24));

      expect(plan.pageCount, greaterThan(1));
      expect(plan.pages.first.startAnchor.textOffset, 0);
      expect(plan.pages.last.endAnchor.textOffset, greaterThan(0));
      for (final page in plan.pages) {
        expect(html_parser.parseFragment(page.html).nodes, isNotEmpty);
      }
      expect(
        plan.pageIndexForAnchor(plan.pages.last.startAnchor),
        plan.pages.last.index,
      );
    },
  );

  test(
    'greedy fill uses remaining height before flushing a text atom',
    () async {
      final chapter = await _prepare('<p>12345678</p><p>abcdefgh</p>');
      final plan = await NovelReaderHtmlPageBreaker(
        measureAdapter: const _TextHeightMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 10));

      expect(plan.pageCount, 2);
      expect(plan.pages.first.fullness, 1);
      expect(
        html_parser.parseFragment(plan.pages.first.html).text,
        '12345678ab',
      );
      expect(html_parser.parseFragment(plan.pages.last.html).text, 'cdefgh');
      expect(
        plan.pages.first.gapReason,
        NovelReaderPageGapReason.algorithmBoundary,
      );
    },
  );

  test('keeps a heading intact instead of splitting its text range', () async {
    final chapter = await _prepare('<p>前置正文</p><h2>这是一个完整标题</h2><p>后续正文</p>');
    final plan = await NovelReaderHtmlPageBreaker(
      measureAdapter: const _TextHeightMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 10));

    final headingPages = plan.pages
        .where((page) => page.html.contains('<h2>'))
        .toList(growable: false);
    expect(headingPages, hasLength(1));
    expect(headingPages.single.html, contains('<h2>这是一个完整标题</h2>'));
  });

  test('keeps readable image indexes global across page fragments', () async {
    final chapter = await _prepare(
      '<p>图片前</p><img src="data/attachment/forum/one.jpg">'
      '<p>图片后</p>',
    );
    final plan = await NovelReaderHtmlPageBreaker(
      measureAdapter: const _TextHeightMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 6));

    expect(plan.pages.expand((page) => page.imageIndices), contains(0));
    expect(plan.pages.expand((page) => page.imageIndices), isNot(contains(1)));
    expect(plan.pages.every((page) => page.index >= 0), isTrue);
  });

  test('isolates readable images between stable text pages', () async {
    final chapter = await _prepare(
      '<p>图片前正文</p>'
      '<img src="data/attachment/forum/one.jpg">'
      '<p>图片后正文</p>',
    );
    final plan = await NovelReaderHtmlPageBreaker(
      measureAdapter: const _TextHeightMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 20));

    expect(plan.pages, hasLength(3));
    expect(plan.pages[0].containsIsolatedImage, isFalse);
    expect(plan.pages[0].gapReason, NovelReaderPageGapReason.isolatedImage);
    expect(plan.pages[1].containsIsolatedImage, isTrue);
    expect(plan.pages[1].imageIndices, <int>[0]);
    expect(plan.pages[1].gapReason, NovelReaderPageGapReason.isolatedImage);
    expect(plan.pageIndexForAnchor(plan.pages[1].startAnchor), 1);
    expect(plan.pages[2].containsIsolatedImage, isFalse);
    expect(plan.pages[2].gapReason, NovelReaderPageGapReason.naturalEnd);
    expect(plan.atomCount, 3);
    expect(plan.atomKindCounts[NovelReaderPaginationAtomKind.image], 1);
    expect(plan.measurementCount, greaterThanOrEqualTo(3));
    expect(plan.measurementSamples, isNotEmpty);
    expect(plan.measurementSamples.length, lessThanOrEqualTo(64));
  });

  test('image dimensions do not change surrounding text page count', () async {
    final unknown = await _prepare(
      '<p>图片前正文</p>'
      '<img src="data/attachment/forum/one.jpg">'
      '<p>图片后正文</p>',
    );
    final known = await _prepare(
      '<p>图片前正文</p>'
      '<img width="800" height="600" '
      'src="data/attachment/forum/one.jpg">'
      '<p>图片后正文</p>',
    );
    final breaker = NovelReaderHtmlPageBreaker(
      measureAdapter: const _TextHeightMeasureAdapter(),
    );

    final unknownPlan = await breaker.paginate(
      unknown,
      _key(unknown, height: 20),
    );
    final knownPlan = await breaker.paginate(known, _key(known, height: 20));
    final unknownTextPages = unknownPlan.pages
        .where((page) => !page.containsIsolatedImage)
        .length;
    final knownTextPages = knownPlan.pages
        .where((page) => !page.containsIsolatedImage)
        .length;

    expect(unknownTextPages, knownTextPages);
    expect(
      unknownPlan.pages.where((page) => page.containsIsolatedImage),
      hasLength(1),
    );
    expect(
      knownPlan.pages.where((page) => page.containsIsolatedImage),
      hasLength(1),
    );
  });

  test('maps an anchor from a unit in the middle of a page', () async {
    final chapter = await _prepare('<p>第一段</p><p>第二段</p>');
    final plan = await NovelReaderHtmlPageBreaker(
      measureAdapter: const _TextHeightMeasureAdapter(),
    ).paginate(chapter, _key(chapter, height: 8));

    expect(plan.pageCount, 1);
    expect(plan.pageIndexForAnchor(chapter.flowUnits[1].startAnchor), 0);
  });

  test(
    'marks an unbreakable oversized widget instead of creating empty pages',
    () async {
      final chapter = await _prepare('<table><tr><td>不可拆内容</td></tr></table>');
      final plan = await NovelReaderHtmlPageBreaker(
        measureAdapter: const _AlwaysOversizedMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 10));

      expect(plan.pageCount, 1);
      expect(plan.pages.single.hasOverflow, isTrue);
      expect(plan.pages.single.requiresInnerScroll, isTrue);
      expect(plan.pages.single.overflowState, isNot(isNull));
    },
  );

  test('rejects a zero-sized viewport with a finite error', () async {
    final chapter = await _prepare('<p>正文</p>');
    await expectLater(
      NovelReaderHtmlPageBreaker(
        measureAdapter: const _TextHeightMeasureAdapter(),
      ).paginate(chapter, _key(chapter, height: 0)),
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'invalidViewport',
        ),
      ),
    );
  });
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
    typographySignature: 'font=18.5|line=1.6|padding=16',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 1,
  );
}

Future<NovelReaderPreparedChapter> _prepare(String html) {
  const episode = NovelEpisodeItem(
    episodeId: 'pagination-episode',
    novelId: 'pagination-novel',
    sourceTid: '100',
    episodeTitle: '分页测试',
    orderIndex: 0,
  );
  return const DefaultNovelReaderHtmlPreparationService().prepare(
    rawHtml: html,
    episode: episode,
    preferences: NovelHtmlReaderPreferencesAdapter().map(
      NovelReaderPreferences.defaults(),
    ),
    theme: _theme,
    sourceId: episode.episodeId,
    threadId: episode.sourceTid,
    imageCacheOwnerId: episode.sourceTid,
  );
}

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

class _TextHeightMeasureAdapter implements NovelReaderPaginationMeasureAdapter {
  const _TextHeightMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return NovelReaderPaginationMeasureResult(
      height: (html_parser.parseFragment(request.html).text ?? '').runes.length
          .toDouble(),
    );
  }
}

class _AlwaysOversizedMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const _AlwaysOversizedMeasureAdapter();

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    return const NovelReaderPaginationMeasureResult(height: 100);
  }
}
