import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_session_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_prepared_chapter_cache.dart';

void main() {
  test(
    'prepared key eviction preserves peers and fences an old flight',
    () async {
      final cache = NovelReaderPreparedChapterCache();
      final peer = _chapter('<p>peer</p>');
      cache.put('peer', peer);
      final oldGate = Completer<NovelReaderPreparedChapter>();
      final newGate = Completer<NovelReaderPreparedChapter>();
      final old = cache.resolve(key: 'retry', prepare: () => oldGate.future);
      cache.evict('retry');
      final current = cache.resolve(
        key: 'retry',
        prepare: () => newGate.future,
      );
      final fresh = _chapter('<p>fresh</p>');
      newGate.complete(fresh);
      expect(await current, same(fresh));
      oldGate.complete(_chapter('<p>obsolete</p>'));
      await old;
      expect(cache.get('retry'), same(fresh));
      expect(cache.get('peer'), same(peer));
      expect(cache.length, 2);
    },
  );

  test(
    'prepared byte LRU rejects a large replacement and clears accounting',
    () {
      final one = _chapter('<p>one</p>');
      final two = _chapter('<p>two</p>');
      final six = _chapter('<p>six</p>');
      final probe = NovelReaderPreparedChapterCache()
        ..put('one', one)
        ..put('two', two);
      final budget = probe.estimatedRetainedBytes;
      final cache = NovelReaderPreparedChapterCache(
        capacity: 8,
        maxEstimatedBytes: budget,
      );
      cache
        ..put('one', one)
        ..put('two', two);
      expect(cache.get('one'), same(one));
      cache.put('six', six);
      expect(cache.length, 2);
      expect(cache.get('two'), isNull);
      expect(cache.get('one'), same(one));
      expect(cache.get('six'), same(six));
      cache.put('one', _chapter('<p>${'long' * 1000}</p>'));
      expect(cache.get('one'), isNull);
      expect(cache.get('six'), same(six));
      expect(cache.estimatedRetainedBytes, lessThanOrEqualTo(budget));
      cache.evict('six');
      expect(cache.estimatedRetainedBytes, 0);
      cache
        ..put('one', one)
        ..clear();
      expect(cache.estimatedRetainedBytes, 0);
      cache.put('one', one);
      expect(cache.get('one'), same(one));
    },
  );

  test(
    'prepared estimate includes scroll fragments and source projections',
    () {
      final plain = NovelReaderPreparedChapterCache()
        ..put('key', _chapter('<p>A</p>'));
      final projected = NovelReaderPreparedChapterCache()
        ..put(
          'key',
          _chapter(
            '<p>A</p>',
            scrollHtml: '<p>A</p>',
            scrollFragments: const ['<p>A</p>'],
            flowUnits: [
              NovelReaderFlowUnit(
                unitId: 'unit',
                html: '<p>A</p>',
                startAnchor: _anchor,
                endAnchor: _anchor,
                breakability: NovelReaderFlowUnitBreakability.text,
                imageIndices: const [],
                sourceAnchorProjection: NovelReaderSourceAnchorProjection(
                  baseAnchor: _anchor,
                  semanticOffsetsBySourceRuneBoundary: const [0, 1],
                ),
              ),
            ],
          ),
        );
      expect(
        projected.estimatedRetainedBytes,
        greaterThan(plain.estimatedRetainedBytes),
      );
    },
  );

  test(
    'prepared clear isolates old success and error from a new same-key flight',
    () async {
      for (final fail in [false, true]) {
        final cache = NovelReaderPreparedChapterCache();
        final oldGate = Completer<NovelReaderPreparedChapter>();
        final newGate = Completer<NovelReaderPreparedChapter>();
        final old = cache.resolve(key: 'key', prepare: () => oldGate.future);
        final oldFailure = fail ? expectLater(old, throwsStateError) : null;
        cache.clear();
        final current = cache.resolve(
          key: 'key',
          prepare: () => newGate.future,
        );
        if (fail) {
          oldGate.completeError(StateError('old preparation'));
          await oldFailure!;
        } else {
          final obsolete = _chapter('<p>old</p>');
          oldGate.complete(obsolete);
          expect(await old, same(obsolete));
        }
        expect(cache.length, 0);
        expect(cache.estimatedRetainedBytes, 0);
        final joined = cache.resolve(
          key: 'key',
          prepare: () => throw StateError('new flight must remain registered'),
        );
        expect(joined, same(current));
        final fresh = _chapter('<p>new</p>');
        newGate.complete(fresh);
        expect(await current, same(fresh));
        expect(await joined, same(fresh));
        expect(cache.get('key'), same(fresh));
      }
    },
  );

  test(
    'prepared dispose rejects new work and never retains late completion',
    () async {
      for (final fail in [false, true]) {
        final cache = NovelReaderPreparedChapterCache();
        final gate = Completer<NovelReaderPreparedChapter>();
        final pending = cache.resolve(key: 'key', prepare: () => gate.future);
        final failure = fail ? expectLater(pending, throwsStateError) : null;
        cache.dispose();
        final chapter = _chapter('<p>late</p>');
        if (fail) {
          gate.completeError(StateError('late preparation'));
          await failure!;
        } else {
          gate.complete(chapter);
          expect(await pending, same(chapter));
        }
        cache
          ..clear()
          ..put('key', chapter);
        var starts = 0;
        await expectLater(
          cache.resolve(
            key: 'key',
            prepare: () {
              starts += 1;
              return Future.value(chapter);
            },
          ),
          throwsStateError,
        );
        expect(starts, 0);
        expect(cache.isClosed, isTrue);
        expect(cache.length, 0);
        expect(cache.estimatedRetainedBytes, 0);
      }
    },
  );

  test('different preparation wrappers share one cache-owned flight', () async {
    final cache = NovelReaderPreparedChapterCache();
    final delegate = _GatedPreparationService();
    final firstWrapper = NovelReaderCachingHtmlPreparationService(
      delegate: delegate,
      cache: cache,
    );
    final secondWrapper = NovelReaderCachingHtmlPreparationService(
      delegate: delegate,
      cache: cache,
    );
    final first = _prepare(firstWrapper);
    final second = _prepare(secondWrapper);
    expect(first, same(second));
    expect(delegate.calls, 1);
    final chapter = _chapter('<p>shared</p>');
    delegate.gate.complete(chapter);
    expect(await first, same(chapter));
    expect(await second, same(chapter));
    expect(await _prepare(secondWrapper), same(chapter));
    expect(delegate.calls, 1);
  });

  test(
    'reader owner clear and dispose permanently close all four caches',
    () async {
      for (final useClear in [false, true]) {
        final owner = NovelReaderPaginationSessionCache();
        final chapter = _chapter('<p>retained</p>');
        final key = _key(chapter);
        final plan = NovelReaderPaginationPlan(
          key: key,
          episodeId: chapter.episodeId,
          pages: const [],
        );
        final measureRequest = NovelReaderPaginationMeasureRequest(
          html: chapter.html,
          chapter: chapter,
          key: key,
        );
        owner.paginationCache.put(plan);
        owner.measureCache.put(
          measureRequest,
          const NovelReaderPaginationMeasureResult(height: 20),
        );
        owner.preparedChapterCache.put('key', chapter);
        await owner.boundaryCache.resolve(
          request: _boundaryRequest,
          build: _buildBoundary,
        );
        expect(owner.estimatedRetainedBytes, greaterThan(0));
        expect(
          owner.estimatedRetainedBytes,
          owner.paginationCache.estimatedRetainedBytes +
              owner.measureCache.estimatedRetainedBytes +
              owner.boundaryCache.estimatedRetainedBytes +
              owner.preparedChapterCache.estimatedRetainedBytes,
        );
        if (useClear) {
          owner.clear();
        } else {
          owner.dispose();
        }
        owner
          ..clear()
          ..dispose();
        expect(owner.isClosed, isTrue);
        expect(owner.paginationCache.isClosed, isTrue);
        expect(owner.measureCache.isClosed, isTrue);
        expect(owner.boundaryCache.isClosed, isTrue);
        expect(owner.preparedChapterCache.isClosed, isTrue);
        expect(owner.estimatedRetainedBytes, 0);
        expect([
          owner.paginationCache.length,
          owner.measureCache.length,
          owner.boundaryCache.length,
          owner.preparedChapterCache.length,
        ], everyElement(0));
        owner.paginationCache.put(plan);
        expect(owner.paginationCache.get(key), isNull);
        await expectLater(
          owner.measureCache.resolve(
            request: measureRequest,
            measure: () => throw StateError('must not start'),
          ),
          throwsStateError,
        );
        await expectLater(
          owner.boundaryCache.resolve(
            request: _boundaryRequest,
            build: _buildBoundary,
          ),
          throwsStateError,
        );
        await expectLater(
          owner.preparedChapterCache.resolve(
            key: 'key',
            prepare: () => Future.value(chapter),
          ),
          throwsStateError,
        );
      }
    },
  );

  test('owner disposal isolates all late cache completions', () async {
    final owner = NovelReaderPaginationSessionCache();
    final chapter = _chapter('<p>pending</p>');
    final key = _key(chapter);
    final measureGate = Completer<NovelReaderPaginationMeasureResult>();
    final preparedGate = Completer<NovelReaderPreparedChapter>();
    final measurement = owner.measureCache.resolve(
      request: NovelReaderPaginationMeasureRequest(
        html: chapter.html,
        chapter: chapter,
        key: key,
      ),
      measure: () => measureGate.future,
    );
    final preparation = owner.preparedChapterCache.resolve(
      key: 'key',
      prepare: () => preparedGate.future,
    );
    final boundary = owner.boundaryCache.resolve(
      request: _boundaryRequest,
      build: _buildBoundary,
    );
    owner.dispose();
    measureGate.complete(const NovelReaderPaginationMeasureResult(height: 30));
    preparedGate.complete(chapter);
    await Future.wait<Object>([measurement, preparation, boundary]);
    owner.paginationCache.put(
      NovelReaderPaginationPlan(
        key: key,
        episodeId: chapter.episodeId,
        pages: const [],
      ),
    );
    expect(owner.estimatedRetainedBytes, 0);
    expect([
      owner.paginationCache.length,
      owner.measureCache.length,
      owner.boundaryCache.length,
      owner.preparedChapterCache.length,
    ], everyElement(0));
  });
}

NovelReaderPreparedChapter _chapter(
  String html, {
  String? scrollHtml,
  List<String>? scrollFragments,
  List<NovelReaderFlowUnit> flowUnits = const [],
}) => NovelReaderPreparedChapter(
  episodeId: _episode.episodeId,
  contentHash: 'content',
  html: html,
  scrollHtml: scrollHtml,
  scrollFragments: scrollFragments,
  flowUnits: flowUnits,
  themeSignature: 'theme',
  imageDimensionRevision: 1,
  convertedTextNodeCount: 0,
  renderDocument: ForumHtmlPreparedRenderDocument(
    preparedHtml: html,
    sequence: const ForumHtmlReadableImageSequence(
      sourceId: 'source',
      entries: [],
    ),
    attachmentIdsByUrl: const {},
    totalImageCount: 0,
    skippedStickerCount: 0,
    skippedNonNetworkCount: 0,
    duplicatedReadableUrlCount: 0,
    attachmentTaggedCount: 0,
    themeSignature: 'theme',
    themeAdaptationStats: ForumHtmlThemeAdaptationStats.none,
  ),
);

NovelReaderPaginationKey _key(NovelReaderPreparedChapter chapter) =>
    NovelReaderPaginationKey(
      episodeId: chapter.episodeId,
      contentHash: chapter.contentHash,
      viewportWidthPx: 320,
      viewportHeightPx: 600,
      typographySignature: 'type',
      themeSignature: chapter.themeSignature,
      imageDimensionRevision: 1,
      rendererRevision: 18,
    );

Future<NovelReaderPreparedChapter> _prepare(
  NovelReaderCachingHtmlPreparationService service,
) => service.prepare(
  rawHtml: '<p>shared</p>',
  episode: _episode,
  preferences: ForumHtmlReaderPreferences.defaults(),
  theme: _theme,
  sourceId: 'source',
  threadId: '100',
  imageCacheOwnerId: '100',
);

const _anchor = NovelReaderTextAnchor(episodeId: 'episode', nodeId: 'node');
const _boundaryRequest = NovelReaderComplexHtmlBoundaryCacheRequest(
  episodeId: 'episode',
  contentHash: 'content',
  atomId: 'atom',
  html: '<p>boundary</p>',
  startAnchor: _anchor,
  normalizerRevision: 1,
);
NovelReaderComplexHtmlSliceSession _buildBoundary() =>
    const DefaultNovelReaderComplexHtmlBoundaryIndexer().prepare(
      html: _boundaryRequest.html,
      startAnchor: _anchor,
    );
const _episode = NovelEpisodeItem(
  episodeId: 'episode',
  novelId: 'novel',
  sourceTid: '100',
  sourcePid: '200',
  sourcePage: 1,
  episodeTitle: 'fixture',
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

class _GatedPreparationService implements NovelReaderHtmlPreparationService {
  final gate = Completer<NovelReaderPreparedChapter>();
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
  }) {
    calls += 1;
    return gate.future;
  }
}
