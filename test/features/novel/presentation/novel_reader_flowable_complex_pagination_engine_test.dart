import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_fit_searcher.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_flowable_complex_pagination_engine.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_layout_policy_resolver.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  late NovelReaderPreparedChapter chapter;
  late NovelReaderPaginationKey key;

  setUp(() {
    chapter = _chapter();
    key = _key(chapter);
  });

  test('keeps a fitting whole atom on the current page', () async {
    final session = _RecordingSession((request) {
      return request.html.startsWith('<p>前文</p>') ? 60 : 40;
    });

    final result = await _paginate(
      text: '复杂标题',
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '<p>前文</p>',
        hasBufferedContent: true,
        availableHeight: 100,
      ),
      chapter: chapter,
      key: key,
      session: session,
    );

    expect(result.requiresAtomicFallback, isFalse);
    expect(result.chunks, hasLength(1));
    expect(result.chunks.single.requiresFreshPage, isFalse);
    expect(result.chunks.single.flushAfterAppend, isFalse);
    expect(result.chunks.single.composedHeight, 60);
    expect(result.probeCount, 1);
    expect(result.cacheHitCount, 1);
    expect(session.requests, hasLength(1));
  });

  test('splits a long atom into continuous page-sized chunks', () async {
    final session = _RecordingSession(_rangeHeight);

    final result = await _paginate(
      text: 'abcdefghijkl',
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '',
        hasBufferedContent: false,
        availableHeight: 40,
      ),
      chapter: chapter,
      key: key,
      session: session,
    );

    expect(result.requiresAtomicFallback, isFalse);
    expect(result.chunks, hasLength(3));
    expect(result.chunks.map((chunk) => chunk.slice.startOffset), <int>[
      0,
      4,
      8,
    ]);
    expect(result.chunks.map((chunk) => chunk.slice.endOffset), <int>[
      4,
      8,
      12,
    ]);
    expect(result.chunks.map((chunk) => chunk.flushAfterAppend), <bool>[
      true,
      true,
      false,
    ]);
    for (var index = 1; index < result.chunks.length; index += 1) {
      expect(
        result.chunks[index - 1].slice.endAnchor.textOffset,
        result.chunks[index].slice.startAnchor.textOffset,
      );
    }
  });

  test(
    'bounded candidates retain near-linear cumulative cost as the atom grows',
    () async {
      final maximumLengths = <int>[];
      final costsPerPage = <double>[];
      for (final length in [96, 384, 1536]) {
        final text = List<String>.filled(length, '甲').join();
        final session = _RecordingSession(_rangeHeight);
        final result = await _paginate(
          text: text,
          page: const NovelReaderPaginationPageContext(
            bufferedHtml: '',
            hasBufferedContent: false,
            availableHeight: 80,
          ),
          chapter: chapter,
          key: key,
          session: session,
        );
        expect(result.requiresAtomicFallback, isFalse);
        expect(result.chunks, hasLength(length ~/ 8));
        expect(
          result.chunks
              .map((chunk) => html_parser.parseFragment(chunk.slice.html).text)
              .join(),
          text,
        );
        expect(
          session.requests.every(
            (request) => request.endOffset! - request.startOffset! <= 64,
          ),
          isTrue,
        );
        final lengths = session.requests.map((request) => request.html.length);
        final maximum = lengths.reduce((a, b) => a > b ? a : b);
        final total = lengths.fold<int>(0, (sum, length) => sum + length);
        maximumLengths.add(maximum);
        costsPerPage.add(total / result.chunks.length);
        debugPrint(
          '[NovelPaginationBounded] text=$length, '
          'pages=${result.chunks.length}, probes=${session.requests.length}, '
          'maxHtmlCodeUnits=$maximum, cumulativeHtmlCodeUnits=$total',
        );
      }
      expect(maximumLengths.toSet(), hasLength(1));
      final minimumCost = costsPerPage.reduce((a, b) => a < b ? a : b);
      final maximumCost = costsPerPage.reduce((a, b) => a > b ? a : b);
      expect(maximumCost, lessThanOrEqualTo(minimumCost * 1.5));
    },
  );

  test('later chunks receive only the previous verified capacity', () async {
    final searcher = _RecordingWindowSearcher();
    final result =
        await DefaultNovelReaderFlowableComplexPaginationEngine(
          fitSearcher: searcher,
        ).paginate(
          atom: _atom('abcdefghijkl'),
          page: const NovelReaderPaginationPageContext(
            bufferedHtml: '',
            hasBufferedContent: false,
            availableHeight: 40,
          ),
          chapter: chapter,
          key: key,
          measureSession: _RecordingSession(_rangeHeight),
          cancellationToken: NovelReaderPaginationCancellationToken(),
        );
    expect(result.chunks, hasLength(3));
    expect(searcher.preferredWindows, <int?>[null, 4, 4]);
  });

  for (final code in [
    'complexFitSearchCandidateLimitExceeded',
    'complexFitSearchBudgetUnavailable',
  ]) {
    test('propagates $code without returning a whole-atom fallback', () async {
      final session = _RecordingSession(_rangeHeight);
      await expectLater(
        DefaultNovelReaderFlowableComplexPaginationEngine(
          fitSearcher: _FailingFitSearcher(code),
        ).paginate(
          atom: _atom('bounded failure'),
          page: const NovelReaderPaginationPageContext(
            bufferedHtml: '',
            hasBufferedContent: false,
            availableHeight: 100,
          ),
          chapter: chapter,
          key: key,
          measureSession: session,
          cancellationToken: NovelReaderPaginationCancellationToken(),
        ),
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
      expect(session.requests, isEmpty);
    });
  }

  for (final height in [80.0, 200.0]) {
    test(
      'an oversized indivisible minimum at height $height is measured once',
      () async {
        final text = List.filled(9000, '甲').join();
        final session = _RecordingSession((_) => height);
        final result =
            await const DefaultNovelReaderFlowableComplexPaginationEngine()
                .paginate(
                  atom: _atom(
                    '<ruby>$text<rt>注</rt></ruby>',
                    route: NovelReaderPaginationRoute.rubyInline,
                  ),
                  page: const NovelReaderPaginationPageContext(
                    bufferedHtml: '',
                    hasBufferedContent: false,
                    availableHeight: 100,
                  ),
                  chapter: chapter,
                  key: key,
                  measureSession: session,
                  cancellationToken: NovelReaderPaginationCancellationToken(),
                );
        expect(session.requests, hasLength(1));
        expect(result.minimumFragmentCount, 1);
        if (height < 100) {
          expect(result.requiresAtomicFallback, isFalse);
          expect(result.chunks, hasLength(1));
          expect(result.measuredMinimumAtomHeight, isNull);
        } else {
          expect(
            result.fallbackReason,
            NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow,
          );
          expect(result.measuredMinimumAtomHeight, height);
          expect(result.measuredMinimumAtomHtml, session.requests.single.html);
        }
      },
    );
  }

  test(
    'retries a whole atom on a fresh page when minimum cannot fit',
    () async {
      final session = _RecordingSession((request) {
        final rangeHeight = _rangeHeight(request);
        return request.html.startsWith('<p>buffer</p>')
            ? rangeHeight + 95
            : rangeHeight;
      });

      final result = await _paginate(
        text: 'abcd',
        page: const NovelReaderPaginationPageContext(
          bufferedHtml: '<p>buffer</p>',
          hasBufferedContent: true,
          availableHeight: 100,
        ),
        chapter: chapter,
        key: key,
        session: session,
      );

      expect(result.chunks, hasLength(1));
      expect(result.chunks.single.requiresFreshPage, isTrue);
      expect(result.chunks.single.flushAfterAppend, isFalse);
      expect(result.chunks.single.composedHeight, 40);
    },
  );

  test(
    'returns an explicit fallback when a minimum fragment overflows',
    () async {
      final result = await _paginate(
        text: 'abcd',
        page: const NovelReaderPaginationPageContext(
          bufferedHtml: '',
          hasBufferedContent: false,
          availableHeight: 100,
        ),
        chapter: chapter,
        key: key,
        session: _RecordingSession((_) => 200),
      );

      expect(result.chunks, isEmpty);
      expect(
        result.fallbackReason,
        NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow,
      );
      expect(result.minimumFragmentCount, 1);
      expect(result.measuredMinimumAtomHeight, isNull);
      expect(result.measuredMinimumAtomHtml, isNull);
    },
  );

  test('maps non-monotonic measurements to an atomic fallback', () async {
    final result = await _paginate(
      text: 'abcdefghij',
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '',
        hasBufferedContent: false,
        availableHeight: 80,
      ),
      chapter: chapter,
      key: key,
      session: _RecordingSession((request) {
        return switch (request.endOffset!) {
          10 => 100,
          5 => 70,
          7 => 60,
          final offset => offset * 10.0,
        };
      }),
    );

    expect(
      result.fallbackReason,
      NovelReaderFlowableComplexFallbackReason.nonMonotonicMeasurement,
    );
    expect(result.chunks, isEmpty);
  });

  test('accepts the ruby route with the shared DOM-range policy', () async {
    const engine = DefaultNovelReaderFlowableComplexPaginationEngine();
    final atom = _atom('ruby', route: NovelReaderPaginationRoute.rubyInline);

    final result = await engine.paginate(
      atom: atom,
      page: const NovelReaderPaginationPageContext(
        bufferedHtml: '',
        hasBufferedContent: false,
        availableHeight: 100,
      ),
      chapter: chapter,
      key: key,
      measureSession: _RecordingSession(_rangeHeight),
      cancellationToken: NovelReaderPaginationCancellationToken(),
    );

    expect(result.requiresAtomicFallback, isFalse);
    expect(result.chunks, hasLength(1));
  });

  test('reuses a boundary session across production engine calls', () async {
    final cache = NovelReaderComplexHtmlBoundaryCache();
    final indexer = _TimedBoundaryIndexer();
    final engine = DefaultNovelReaderFlowableComplexPaginationEngine(
      boundaryCache: cache,
      boundaryIndexer: indexer,
    );
    final atom = _atom('cached complex text');
    const page = NovelReaderPaginationPageContext(
      bufferedHtml: '',
      hasBufferedContent: false,
      availableHeight: 400,
    );

    final firstPending = engine.paginate(
      atom: atom,
      page: page,
      chapter: chapter,
      key: key,
      measureSession: _RecordingSession(_rangeHeight),
      cancellationToken: NovelReaderPaginationCancellationToken(),
    );
    final joinedPending = engine.paginate(
      atom: atom,
      page: page,
      chapter: chapter,
      key: key,
      measureSession: _RecordingSession(_rangeHeight),
      cancellationToken: NovelReaderPaginationCancellationToken(),
    );
    final first = await firstPending;
    final joined = await joinedPending;
    final second = await engine.paginate(
      atom: atom,
      page: page,
      chapter: chapter,
      key: key,
      measureSession: _RecordingSession(_rangeHeight),
      cancellationToken: NovelReaderPaginationCancellationToken(),
    );

    expect(first.boundaryIndexBuildCount, 1);
    expect(
      first.boundaryIndexBuildDuration,
      greaterThanOrEqualTo(indexer.prepareDuration),
    );
    expect(first.boundaryIndexCacheHitCount, 0);
    expect(joined.boundaryIndexBuildCount, 0);
    expect(joined.boundaryIndexSingleFlightHitCount, 1);
    expect(joined.boundaryIndexBuildDuration, Duration.zero);
    expect(second.boundaryIndexBuildCount, 0);
    expect(second.boundaryIndexBuildDuration, Duration.zero);
    expect(second.boundaryIndexCacheHitCount, 1);
    expect(indexer.prepareCount, 1);
    expect(cache.length, 1);
  });

  test('records boundary build duration even when preparation fails', () async {
    for (final cache in <NovelReaderComplexHtmlBoundaryCache?>[
      null,
      NovelReaderComplexHtmlBoundaryCache(),
    ]) {
      final indexer = _TimedBoundaryIndexer(fail: true);
      final session = _RecordingSession(_rangeHeight);
      final result =
          await DefaultNovelReaderFlowableComplexPaginationEngine(
            boundaryIndexer: indexer,
            boundaryCache: cache,
          ).paginate(
            atom: _atom('failed complex indexing'),
            page: const NovelReaderPaginationPageContext(
              bufferedHtml: '',
              hasBufferedContent: false,
              availableHeight: 400,
            ),
            chapter: chapter,
            key: key,
            measureSession: session,
            cancellationToken: NovelReaderPaginationCancellationToken(),
          );

      expect(indexer.prepareCount, 1);
      expect(result.boundaryIndexBuildCount, 1);
      expect(
        result.boundaryIndexBuildDuration,
        greaterThanOrEqualTo(indexer.prepareDuration),
      );
      expect(
        result.fallbackReason,
        NovelReaderFlowableComplexFallbackReason.boundaryIndexFailure,
      );
      expect(result.chunks, isEmpty);
      expect(session.requests, isEmpty);
    }
  });

  test(
    'complex chunks retain DOM text and project absolute semantic offsets',
    () async {
      const text = 'e\u0301  中';
      final anchor =
          const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'node-1',
            textOffset: 7,
            formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
          ).copyWith(
            textIdentity: NovelReaderAnchorFormat.textIdentity(
              '前文前文前文前e\u0301 中',
            ),
          );
      final projection = NovelReaderSourceAnchorProjection(
        baseAnchor: anchor,
        semanticOffsetsBySourceRuneBoundary: const [7, 8, 9, 10, 10, 11],
      );
      final result =
          await const DefaultNovelReaderFlowableComplexPaginationEngine()
              .paginate(
                atom: _atom(text, sourceAnchorProjection: projection),
                page: const NovelReaderPaginationPageContext(
                  bufferedHtml: '',
                  hasBufferedContent: false,
                  availableHeight: 20,
                ),
                chapter: chapter,
                key: key,
                measureSession: _RecordingSession(_rangeHeight),
                cancellationToken: NovelReaderPaginationCancellationToken(),
              );

      expect(result.requiresAtomicFallback, isFalse);
      expect(result.chunks, hasLength(2));
      expect(
        result.chunks
            .map((chunk) => html_parser.parseFragment(chunk.slice.html).text)
            .join(),
        text,
      );
      expect(result.chunks.map((chunk) => chunk.slice.startOffset), <int>[
        0,
        2,
      ]);
      expect(result.chunks.map((chunk) => chunk.slice.endOffset), <int>[2, 4]);
      expect(
        result.chunks.map((chunk) => chunk.slice.startAnchor.textOffset),
        <int>[7, 10],
      );
      expect(
        result.chunks.map((chunk) => chunk.slice.endAnchor.textOffset),
        <int>[10, 11],
      );
      expect(
        result.chunks.every(
          (chunk) =>
              chunk.slice.startAnchor.textIdentity == anchor.textIdentity &&
              chunk.slice.endAnchor.hasCanonicalTextOffset,
        ),
        isTrue,
      );
    },
  );

  test(
    'engine boundary cache follows the atom projection rather than HTML alone',
    () async {
      final engine = DefaultNovelReaderFlowableComplexPaginationEngine(
        boundaryCache: NovelReaderComplexHtmlBoundaryCache(),
      );
      final anchor =
          const NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'node-1',
            textOffset: 5,
            formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
          ).copyWith(
            textIdentity: NovelReaderAnchorFormat.textIdentity('前文前文前A B'),
          );
      Future<NovelReaderFlowableComplexPaginationResult> paginate(
        List<int> offsets,
      ) {
        return engine.paginate(
          atom: _atom(
            'A  B',
            sourceAnchorProjection: NovelReaderSourceAnchorProjection(
              baseAnchor: anchor,
              semanticOffsetsBySourceRuneBoundary: offsets,
            ),
          ),
          page: const NovelReaderPaginationPageContext(
            bufferedHtml: '',
            hasBufferedContent: false,
            availableHeight: 100,
          ),
          chapter: chapter,
          key: key,
          measureSession: _RecordingSession(_rangeHeight),
          cancellationToken: NovelReaderPaginationCancellationToken(),
        );
      }

      final folded = await paginate(const [5, 6, 7, 7, 8]);
      final expanded = await paginate(const [5, 6, 7, 8, 9]);
      final foldedAgain = await paginate(const [5, 6, 7, 7, 8]);
      expect(folded.chunks.single.slice.endAnchor.textOffset, 8);
      expect(expanded.chunks.single.slice.endAnchor.textOffset, 9);
      expect(foldedAgain.chunks.single.slice.endAnchor.textOffset, 8);
      expect(folded.boundaryIndexBuildCount, 1);
      expect(expanded.boundaryIndexBuildCount, 1);
      expect(expanded.boundaryIndexCacheHitCount, 0);
      expect(foldedAgain.boundaryIndexBuildCount, 0);
      expect(foldedAgain.boundaryIndexCacheHitCount, 1);
    },
  );

  test('rejects a route without the DOM-range flow policy', () async {
    const engine = DefaultNovelReaderFlowableComplexPaginationEngine();
    final atom = _atom(
      'widget',
      route: NovelReaderPaginationRoute.atomicWidget,
    );

    await expectLater(
      engine.paginate(
        atom: atom,
        page: const NovelReaderPaginationPageContext(
          bufferedHtml: '',
          hasBufferedContent: false,
          availableHeight: 100,
        ),
        chapter: chapter,
        key: key,
        measureSession: _RecordingSession(_rangeHeight),
        cancellationToken: NovelReaderPaginationCancellationToken(),
      ),
      throwsArgumentError,
    );
  });
}

Future<NovelReaderFlowableComplexPaginationResult> _paginate({
  required String text,
  required NovelReaderPaginationPageContext page,
  required NovelReaderPreparedChapter chapter,
  required NovelReaderPaginationKey key,
  required NovelReaderPaginationMeasureSession session,
}) {
  return const DefaultNovelReaderFlowableComplexPaginationEngine().paginate(
    atom: _atom(text),
    page: page,
    chapter: chapter,
    key: key,
    measureSession: session,
    cancellationToken: NovelReaderPaginationCancellationToken(),
  );
}

NovelReaderClassifiedPaginationAtom _atom(
  String text, {
  NovelReaderPaginationRoute route =
      NovelReaderPaginationRoute.flowableComplexText,
  NovelReaderSourceAnchorProjection? sourceAnchorProjection,
}) {
  final atom = NovelReaderPaginationAtom(
    atomId: 'complex:1',
    kind: NovelReaderPaginationAtomKind.text,
    html: '<font face="Fantasy Novel Font">$text</font>',
    startAnchor:
        sourceAnchorProjection?.anchorAtSourceRune(0) ??
        const NovelReaderTextAnchor(episodeId: 'episode-1', nodeId: 'node-1'),
    endAnchor: sourceAnchorProjection == null
        ? NovelReaderTextAnchor(
            episodeId: 'episode-1',
            nodeId: 'node-1',
            textOffset: text.length,
          )
        : sourceAnchorProjection.anchorAtSourceRune(
            sourceAnchorProjection.sourceRuneLength,
          ),
    textLength: text.length,
    imageIndices: const <int>[],
    breakability: NovelReaderFlowUnitBreakability.text,
    imagePagePolicy: NovelReaderImagePagePolicy.inline,
    sourceAnchorProjection: sourceAnchorProjection,
  );
  return NovelReaderClassifiedPaginationAtom(
    atom: atom,
    route: route,
    reason: switch (route) {
      NovelReaderPaginationRoute.flowableComplexText =>
        NovelReaderPaginationRouteReason.unsupportedFont,
      NovelReaderPaginationRoute.rubyInline =>
        NovelReaderPaginationRouteReason.containsRuby,
      _ => NovelReaderPaginationRouteReason.atomicWidget,
    },
    layoutPolicy: const DefaultNovelReaderPaginationLayoutPolicyResolver()
        .resolve(route),
  );
}

double _rangeHeight(NovelReaderPaginationMeasureRequest request) {
  return (request.endOffset! - request.startOffset!) * 10.0;
}

NovelReaderPreparedChapter _chapter() {
  const html = '<p>chapter</p>';
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: _theme,
    sourceId: 'episode-1',
    threadId: null,
    imageCacheOwnerId: null,
  );
  return NovelReaderPreparedChapter(
    episodeId: 'episode-1',
    contentHash: 'content-1',
    html: document.preparedHtml,
    renderDocument: document,
    flowUnits: const [],
    themeSignature: document.themeSignature,
    imageDimensionRevision: 1,
    convertedTextNodeCount: 0,
  );
}

NovelReaderPaginationKey _key(NovelReaderPreparedChapter chapter) {
  return NovelReaderPaginationKey(
    episodeId: chapter.episodeId,
    contentHash: chapter.contentHash,
    viewportWidthPx: 320,
    viewportHeightPx: 100,
    typographySignature: 'font=18.5|line=1.6',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 13,
  );
}

typedef _HeightResolver =
    double Function(NovelReaderPaginationMeasureRequest request);

final class _TimedBoundaryIndexer
    implements NovelReaderComplexHtmlBoundaryIndexer {
  _TimedBoundaryIndexer({this.fail = false});

  final bool fail;
  int prepareCount = 0;
  Duration prepareDuration = Duration.zero;

  @override
  NovelReaderComplexHtmlSliceSession prepare({
    required String html,
    required NovelReaderTextAnchor startAnchor,
    NovelReaderSourceAnchorProjection? sourceAnchorProjection,
  }) {
    prepareCount += 1;
    final stopwatch = Stopwatch()..start();
    try {
      final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
          .prepare(
            html: html,
            startAnchor: startAnchor,
            sourceAnchorProjection: sourceAnchorProjection,
          );
      if (fail) {
        throw StateError('synthetic boundary indexing failure');
      }
      return session;
    } finally {
      stopwatch.stop();
      prepareDuration = stopwatch.elapsed;
    }
  }
}

final class _RecordingWindowSearcher
    implements NovelReaderComplexHtmlFitSearcher {
  final preferredWindows = <int?>[];

  @override
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
    int? preferredWindowGraphemes,
  }) {
    preferredWindows.add(preferredWindowGraphemes);
    return const DefaultNovelReaderComplexHtmlFitSearcher()
        .findLargestFittingPrefix(
          session: session,
          startOffset: startOffset,
          bufferedPageHtml: bufferedPageHtml,
          availableHeight: availableHeight,
          context: context,
          cancellationToken: cancellationToken,
          preferredWindowGraphemes: preferredWindowGraphemes,
        );
  }
}

final class _FailingFitSearcher implements NovelReaderComplexHtmlFitSearcher {
  const _FailingFitSearcher(this.code);

  final String code;

  @override
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
    int? preferredWindowGraphemes,
  }) async {
    throw NovelReaderPaginationException(
      code: code,
      message: 'Controlled bounded search failure.',
    );
  }
}

final class _RecordingSession implements NovelReaderPaginationMeasureSession {
  _RecordingSession(this.heightResolver);

  final _HeightResolver heightResolver;
  final List<NovelReaderPaginationMeasureRequest> requests =
      <NovelReaderPaginationMeasureRequest>[];

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    requests.add(request);
    return NovelReaderPaginationMeasureResult(height: heightResolver(request));
  }

  @override
  Future<void> dispose() async {}
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
