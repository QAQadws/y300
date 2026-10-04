import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/services/novel_html_reader_preferences_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_flow_unit_extractor.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_legacy_markup_normalizer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

void main() {
  const service = DefaultNovelReaderHtmlPreparationService();
  const adapter = NovelHtmlReaderPreferencesAdapter();

  test(
    'converted text cannot acquire a different semantic node through a spelling collision',
    () async {
      const rawHtml = '<p>臺</p><p>台</p>';
      final semantic = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: _episode.episodeId,
        rawHtml: rawHtml,
        fallbackParagraphs: const <String>[],
      );
      final prepared =
          await const DefaultNovelReaderHtmlPreparationService(
            preparer: _ConvertedChapterPreparer(),
          ).prepare(
            rawHtml: rawHtml,
            episode: _episode,
            preferences: adapter
                .map(NovelReaderPreferences.defaults())
                .copyWith(conversionMode: TextConversionMode.toSimplified),
            theme: _theme,
            sourceId: _episode.episodeId,
            threadId: _episode.sourceTid,
            imageCacheOwnerId: _episode.sourceTid,
            semanticDocument: semantic,
          );
      expect(prepared.convertedTextNodeCount, 1);
      expect(prepared.flowUnits, hasLength(2));
      expect(
        prepared.flowUnits[0].startAnchor.nodeId,
        startsWith('novel-html-'),
      );
      expect(
        prepared.flowUnits[1].startAnchor.nodeId,
        startsWith('novel-html-'),
      );
      expect(
        prepared.flowUnits[0].startAnchor.nodeId,
        isNot(prepared.flowUnits[1].startAnchor.nodeId),
      );
      expect(
        prepared.flowUnits.every(
          (unit) => unit.startAnchor.hasCanonicalTextOffset,
        ),
        isTrue,
      );
    },
  );

  test(
    'matching conversion provenance retains a unique semantic node',
    () async {
      const convertedHtml = '<p>台正文</p>';
      final parsed = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: _episode.episodeId,
        rawHtml: convertedHtml,
        fallbackParagraphs: const <String>[],
      );
      final semantic = _withConversionIdentity(
        parsed,
        TextConversionMode.toSimplified.name,
      );
      final prepared =
          await const DefaultNovelReaderHtmlPreparationService(
            preparer: _ConvertedChapterPreparer(),
          ).prepare(
            rawHtml: '<p>臺正文</p>',
            episode: _episode,
            preferences: adapter
                .map(NovelReaderPreferences.defaults())
                .copyWith(conversionMode: TextConversionMode.toSimplified),
            theme: _theme,
            sourceId: _episode.episodeId,
            threadId: _episode.sourceTid,
            imageCacheOwnerId: _episode.sourceTid,
            semanticDocument: semantic,
          );

      expect(prepared.convertedTextNodeCount, 1);
      expect(
        prepared.flowUnits.single.startAnchor.nodeId,
        semantic.blocks.single.anchorId,
      );
      expect(
        prepared.flowUnits.single.startAnchor.hasCanonicalTextOffset,
        isTrue,
      );
      expect(prepared.flowUnits.single.endAnchor.textOffset, 3);
    },
  );

  test(
    'same semantic HTML hash with different modes cannot share prepared cache',
    () async {
      final parsed = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: _episode.episodeId,
        rawHtml: '<p>台正文</p>',
        fallbackParagraphs: const <String>[],
      );
      final matching = _withConversionIdentity(
        parsed,
        TextConversionMode.toSimplified.name,
      );
      final cache = NovelReaderPreparedChapterCache();
      final service = NovelReaderCachingHtmlPreparationService(
        delegate: const DefaultNovelReaderHtmlPreparationService(
          preparer: _ConvertedChapterPreparer(),
        ),
        cache: cache,
      );
      final preferences = adapter
          .map(NovelReaderPreferences.defaults())
          .copyWith(conversionMode: TextConversionMode.toSimplified);
      Future<NovelReaderPreparedChapter> prepare(
        NovelReaderDocument semantic,
      ) => service.prepare(
        rawHtml: '<p>臺正文</p>',
        episode: _episode,
        preferences: preferences,
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
        semanticDocument: semantic,
      );

      expect(parsed.rawHtmlHash, matching.rawHtmlHash);
      final oldMode = prepare(parsed);
      final currentMode = prepare(matching);
      expect(identical(oldMode, currentMode), isFalse);
      final oldPrepared = await oldMode;
      final currentPrepared = await currentMode;
      expect(
        oldPrepared.flowUnits.single.startAnchor.nodeId,
        startsWith('novel-html-'),
      );
      expect(
        currentPrepared.flowUnits.single.startAnchor.nodeId,
        matching.blocks.single.anchorId,
      );
      expect(cache.length, 2);
      expect(await prepare(parsed), same(oldPrepared));
      expect(await prepare(matching), same(currentPrepared));
    },
  );

  test(
    'previewing none cannot use a semantic document from an earlier conversion',
    () async {
      final parsed = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: _episode.episodeId,
        rawHtml: '<p>相同文字</p>',
        fallbackParagraphs: const <String>[],
      );
      final semantic = _withConversionIdentity(
        parsed,
        TextConversionMode.toSimplified.name,
      );
      final prepared = await service.prepare(
        rawHtml: '<p>相同文字</p>',
        episode: _episode,
        preferences: adapter.map(NovelReaderPreferences.defaults()),
        theme: _theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
        semanticDocument: semantic,
      );

      expect(prepared.convertedTextNodeCount, 0);
      expect(
        prepared.flowUnits.single.startAnchor.nodeId,
        startsWith('novel-html-'),
      );
    },
  );

  test('large background preparation matches synchronous HTML and anchors', () async {
    final body = List.generate(
      220,
      (index) =>
          '<p id="fixture-$index">正文 $index <b>粗体</b>'
          '<font color="#ff0000">颜色</font><a href="https://example.org">链接</a></p>',
    ).join();
    final rawHtml =
        '$body<img width="640" height="480" src="data/attachment/forum/fixture.jpg">'
        '<div class="showcollapse_box"><div class="showcollapse_title">目录</div>'
        '<div class="showcollapse_content">折叠正文</div></div>';
    final preferences = adapter.map(NovelReaderPreferences.defaults());
    final expected = const DefaultForumHtmlRenderPreparer().prepare(
      html: rawHtml,
      preferences: preferences,
      theme: _theme,
      sourceId: _episode.episodeId,
      threadId: _episode.sourceTid,
      imageCacheOwnerId: _episode.sourceTid,
    );
    final units = const DefaultNovelReaderHtmlFlowUnitExtractor().extract(
      episodeId: _episode.episodeId,
      renderDocument: expected,
    );
    final actual = await service.prepare(
      rawHtml: rawHtml,
      episode: _episode,
      preferences: preferences,
      theme: _theme,
      sourceId: _episode.episodeId,
      threadId: _episode.sourceTid,
      imageCacheOwnerId: _episode.sourceTid,
    );
    expect(actual.renderDocument.preparedHtml, expected.preparedHtml);
    expect(
      actual.flowUnits.map((u) => (u.unitId, u.html, u.endAnchor.textOffset)),
      units.map((u) => (u.unitId, u.html, u.endAnchor.textOffset)),
    );
    expect(
      actual.renderDocument.sequence.entries.single.cacheKey,
      expected.sequence.entries.single.cacheKey,
    );
    expect(actual.html, rawHtml);
  });

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
  test(
    'keeps full Host preferences and theme in prepared cache identity',
    () async {
      final preferences = adapter.map(NovelReaderPreferences.defaults());
      final nextTheme = ForumHtmlThemeContext(
        brightness: _theme.brightness,
        surface: _theme.surface,
        foreground: _theme.foreground,
        link: _theme.link,
        quoteSurface: const Color(0xFFEEDDCC),
        quoteForeground: _theme.quoteForeground,
        codeSurface: _theme.codeSurface,
        codeForeground: _theme.codeForeground,
      );
      final cases = [
        (name: 'baseline', preferences: preferences, theme: _theme),
        (
          name: 'conversion',
          preferences: preferences.copyWith(
            conversionMode: TextConversionMode.toTraditional,
          ),
          theme: _theme,
        ),
        (
          name: 'font scale',
          preferences: preferences.copyWith(
            typography: preferences.typography.copyWith(fontScale: 1.7),
          ),
          theme: _theme,
        ),
        (
          name: 'line height',
          preferences: preferences.copyWith(
            typography: preferences.typography.copyWith(lineHeightScale: 2.1),
          ),
          theme: _theme,
        ),
        (
          name: 'paragraph spacing',
          preferences: preferences.copyWith(
            typography: preferences.typography.copyWith(paragraphSpacing: 28),
          ),
          theme: _theme,
        ),
        (
          name: 'author font size',
          preferences: preferences.copyWith(
            preserveAuthorFontSize: !preferences.preserveAuthorFontSize,
          ),
          theme: _theme,
        ),
        (name: 'theme palette', preferences: preferences, theme: nextTheme),
      ];
      final delegate = _CountingPreparationService();
      final service = NovelReaderCachingHtmlPreparationService(
        delegate: delegate,
        cache: NovelReaderPreparedChapterCache(capacity: cases.length),
      );
      Future<NovelReaderPreparedChapter> prepare(
        ForumHtmlReaderPreferences preferences,
        ForumHtmlThemeContext theme,
      ) => service.prepare(
        rawHtml: '<p>缓存正文</p>',
        episode: _episode,
        preferences: preferences,
        theme: theme,
        sourceId: _episode.episodeId,
        threadId: _episode.sourceTid,
        imageCacheOwnerId: _episode.sourceTid,
      );
      final prepared = <NovelReaderPreparedChapter>[];
      for (final input in cases) {
        prepared.add(await prepare(input.preferences, input.theme));
        expect(delegate.calls, prepared.length, reason: input.name);
      }
      for (var index = 0; index < cases.length; index++) {
        final input = cases[index];
        expect(
          await prepare(input.preferences, input.theme),
          same(prepared[index]),
          reason: input.name,
        );
      }
      expect(delegate.calls, cases.length);
    },
  );
}

NovelReaderDocument _withConversionIdentity(
  NovelReaderDocument document,
  String identity,
) => NovelReaderDocument(
  episodeId: document.episodeId,
  rawHtmlHash: document.rawHtmlHash,
  body: document.body,
  plainText: document.plainText,
  wordCount: document.wordCount,
  textConversionIdentity: identity,
);

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

class _ConvertedChapterPreparer implements NovelHtmlChapterPreparer {
  const _ConvertedChapterPreparer();
  @override
  int get legacyMarkupNormalizerRevision => 1;
  @override
  Future<NovelHtmlPreparedChapter> prepare({
    required String rawHtml,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) async {
    final converted = rawHtml.replaceAll('臺', '台');
    return NovelHtmlPreparedChapter(
      html: converted,
      convertedTextNodeCount: 1,
      document: const DefaultForumHtmlRenderPreparer().prepare(
        html: converted,
        preferences: preferences,
        theme: theme,
        sourceId: sourceId,
        threadId: threadId,
        imageCacheOwnerId: imageCacheOwnerId,
      ),
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
