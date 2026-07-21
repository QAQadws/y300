import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_legacy_markup_normalizer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

void main() {
  const service = DefaultNovelReaderHtmlPreparationService();
  const adapter = NovelHtmlReaderPreferencesAdapter();

  test('prepares one reusable HTML-first visual chapter', () async {
    const rawHtml =
        '<p>第一段<a href="thread-101-1-1.html">链接</a></p>'
        '<img width="640" height="480" '
        'src="data/attachment/forum/page.jpg">';
    final preferences = NovelReaderPreferences.defaults();

    final prepared = await service.prepare(
      rawHtml: rawHtml,
      episode: _episode,
      preferences: adapter.map(preferences),
      theme: _theme,
      sourceId: _episode.episodeId,
      threadId: _episode.sourceTid,
      imageCacheOwnerId: _episode.sourceTid,
    );

    expect(prepared.episodeId, _episode.episodeId);
    expect(prepared.contentHash, hasLength(8));
    expect(prepared.themeSignature, _theme.signature);
    expect(prepared.flowUnits, hasLength(2));
    expect(prepared.renderDocument.sequence.entries, hasLength(1));
    expect(prepared.flowUnits.last.imageIndices, <int>[0]);
    expect(prepared.imageDimensionRevision, isNonZero);
    expect(prepared.html, rawHtml);
    expect(prepared.legacyMarkupNormalization.revision, 1);
    expect(prepared.legacyMarkupNormalization.normalizedAttributeCount, 0);
  });

  test(
    'equal inputs produce stable visual identities and flow units',
    () async {
      const rawHtml = '<p>稳定正文</p><p>第二段</p>';
      final preferences = adapter.map(NovelReaderPreferences.defaults());

      final first = await service.prepare(
        rawHtml: rawHtml,
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );
      final second = await service.prepare(
        rawHtml: rawHtml,
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );

      expect(second.contentHash, first.contentHash);
      expect(second.imageDimensionRevision, first.imageDimensionRevision);
      expect(
        second.flowUnits.map((unit) => unit.unitId),
        first.flowUnits.map((unit) => unit.unitId),
      );
      expect(
        second.renderDocument.sequence.entries.map((entry) => entry.cacheKey),
        first.renderDocument.sequence.entries.map((entry) => entry.cacheKey),
      );
    },
  );

  test('includes the legacy normalizer revision in content identity', () async {
    final preferences = adapter.map(NovelReaderPreferences.defaults());
    final current = await service.prepare(
      rawHtml: '<p>稳定正文</p>',
      episode: _episode,
      preferences: preferences,
      theme: _theme,
      sourceId: _episode.episodeId,
      threadId: _episode.sourceTid,
      imageCacheOwnerId: _episode.sourceTid,
    );
    final legacy =
        await const DefaultNovelReaderHtmlPreparationService(
          preparer: NovelHtmlChapterRenderPreparer(
            legacyMarkupNormalizer: NoopNovelReaderLegacyMarkupNormalizer(),
          ),
        ).prepare(
          rawHtml: '<p>稳定正文</p>',
          episode: _episode,
          preferences: preferences,
          theme: _theme,
          sourceId: _episode.episodeId,
          threadId: _episode.sourceTid,
          imageCacheOwnerId: _episode.sourceTid,
        );

    expect(
      current.renderDocument.preparedHtml,
      legacy.renderDocument.preparedHtml,
    );
    expect(current.legacyMarkupNormalization.revision, 1);
    expect(legacy.legacyMarkupNormalization.revision, 0);
    expect(current.contentHash, isNot(legacy.contentHash));
  });

  test(
    'isolates shared preparation cache entries by normalizer revision',
    () async {
      final cache = NovelReaderPreparedChapterCache();
      final currentService = NovelReaderCachingHtmlPreparationService(
        delegate: const DefaultNovelReaderHtmlPreparationService(),
        cache: cache,
      );
      final legacyService = NovelReaderCachingHtmlPreparationService(
        delegate: const DefaultNovelReaderHtmlPreparationService(
          preparer: NovelHtmlChapterRenderPreparer(
            legacyMarkupNormalizer: NoopNovelReaderLegacyMarkupNormalizer(),
          ),
        ),
        cache: cache,
      );
      final preferences = adapter.map(NovelReaderPreferences.defaults());

      final current = await currentService.prepare(
        rawHtml: '<font face="&amp;quot">正文</font>',
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );
      final legacy = await legacyService.prepare(
        rawHtml: '<font face="&amp;quot">正文</font>',
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );

      expect(cache.length, 2);
      expect(current.legacyMarkupNormalization.revision, 1);
      expect(legacy.legacyMarkupNormalization.revision, 0);
      expect(current.html, isNot(contains('face=')));
      expect(legacy.html, contains('face='));
    },
  );

  test(
    'reuses prepared chapters and coalesces concurrent preparation',
    () async {
      final delegate = _CountingPreparationService();
      final service = NovelReaderCachingHtmlPreparationService(
        delegate: delegate,
        cache: NovelReaderPreparedChapterCache(capacity: 1),
      );
      final preferences = adapter.map(NovelReaderPreferences.defaults());

      final first = service.prepare(
        rawHtml: '<p>缓存正文</p>',
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );
      final second = service.prepare(
        rawHtml: '<p>缓存正文</p>',
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );

      expect(identical(first, second), isTrue);
      expect(await first, isA<NovelReaderPreparedChapter>());
      expect(delegate.calls, 1);

      await service.prepare(
        rawHtml: '<p>缓存正文</p>',
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );
      expect(delegate.calls, 1);
    },
  );
}

class _CountingPreparationService implements NovelReaderHtmlPreparationService {
  int calls = 0;

  @override
  int get legacyMarkupNormalizerRevision => 1;

  @override
  Future<NovelReaderPreparedChapter> prepare({
    required String rawHtml,
    required NovelEpisodeItem episode,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
    NovelReaderDocument? semanticDocument,
  }) async {
    calls += 1;
    return await const DefaultNovelReaderHtmlPreparationService().prepare(
      rawHtml: '<p>缓存正文</p>',
      episode: _episode,
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: _theme,
      sourceId: 'episode-1',
      threadId: '100',
      imageCacheOwnerId: '100',
    );
  }
}

const _episode = NovelEpisodeItem(
  episodeId: 'episode-1',
  novelId: 'novel-1',
  sourceTid: '100',
  sourcePid: '200',
  sourcePage: 1,
  episodeTitle: '第一章',
  orderIndex: 0,
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
