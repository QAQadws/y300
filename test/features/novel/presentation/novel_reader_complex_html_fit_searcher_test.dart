import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_fit_searcher.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  late NovelReaderPreparedChapter chapter;
  late NovelReaderPaginationKey key;

  setUp(() {
    chapter = _chapter();
    key = _key(chapter);
  });

  test('whole remainder fast check accepts an exact full fit', () async {
    final sliceSession = _sliceSession('abcde');
    final measurer = _RecordingMeasureSession(_linearHeight);

    final result = await _search(
      sliceSession: sliceSession,
      measurer: measurer,
      chapter: chapter,
      key: key,
      availableHeight: 50,
    );

    expect(result.slice.endOffset, 5);
    expect(result.measuredHeight, 50);
    expect(result.fits, isTrue);
    expect(result.exhaustedAtom, isTrue);
    expect(result.probeCount, 1);
    expect(result.cacheHitCount, 1);
    expect(measurer.probedOffsets, <int>[5]);
  });

  test(
    'returns the largest measured fitting boundary for a partial fit',
    () async {
      final sliceSession = _sliceSession('abcde');
      final measurer = _RecordingMeasureSession(_linearHeight);

      final result = await _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 30,
      );

      expect(result.slice.endOffset, 3);
      expect(result.measuredHeight, 30);
      expect(result.fits, isTrue);
      expect(result.exhaustedAtom, isFalse);
      expect(measurer.probedOffsets, contains(result.slice.endOffset));
      expect(
        measurer.probedOffsets
            .where((offset) => offset > result.slice.endOffset)
            .every((offset) => offset * 10 > 30),
        isTrue,
      );
    },
  );

  test(
    'returns a measured minimum fragment when every candidate overflows',
    () async {
      final sliceSession = _sliceSession('abcd');
      final measurer = _RecordingMeasureSession(_linearHeight);

      final result = await _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 5,
      );

      expect(result.slice.endOffset, 1);
      expect(result.measuredHeight, 10);
      expect(result.fits, isFalse);
      expect(result.requiresFreshPage, isFalse);
      expect(measurer.probedOffsets, <int>[4, 1]);
    },
  );

  test(
    'keeps the minimum boundary when it is the only fitting prefix',
    () async {
      final sliceSession = _sliceSession('abcdef');
      final measurer = _RecordingMeasureSession(_linearHeight);

      final result = await _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 10,
      );

      expect(result.slice.endOffset, 1);
      expect(result.fits, isTrue);
      expect(result.exhaustedAtom, isFalse);
    },
  );

  test('flushes a non-empty page and retries against a fresh page', () async {
    final sliceSession = _sliceSession('abcd');
    final measurer = _RecordingMeasureSession((request) {
      final fragmentHeight = (request.endOffset! - request.startOffset!) * 10.0;
      return request.html.startsWith('<p>buffer</p>')
          ? fragmentHeight + 100
          : fragmentHeight;
    });

    final result = await _search(
      sliceSession: sliceSession,
      measurer: measurer,
      chapter: chapter,
      key: key,
      bufferedPageHtml: '<p>buffer</p>',
      availableHeight: 25,
    );

    expect(result.requiresFreshPage, isTrue);
    expect(result.slice.endOffset, 2);
    expect(result.measuredHeight, 20);
    expect(result.fits, isTrue);
    expect(
      measurer.requests
          .take(2)
          .every((request) => request.html.startsWith('<p>buffer</p>')),
      isTrue,
    );
    expect(
      measurer.requests
          .skip(2)
          .every((request) => !request.html.startsWith('<p>buffer</p>')),
      isTrue,
    );
  });

  test(
    'searches semantic boundaries before refining grapheme boundaries',
    () async {
      final sliceSession = _sliceSession('aaaa bbbb。cccc');
      final measurer = _RecordingMeasureSession(_linearHeight);

      final result = await _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 80,
      );

      expect(result.slice.endOffset, 8);
      expect(measurer.probedOffsets.take(4), <int>[14, 1, 5, 10]);
      expect(
        measurer.probedOffsets.indexOf(5),
        lessThan(measurer.probedOffsets.indexOf(7)),
      );
    },
  );

  test('stops at twelve probes and returns only a verified fit', () async {
    final sliceSession = _sliceSession(List.filled(4096, 'a').join());
    final measurer = _RecordingMeasureSession(_linearHeight);

    final result = await _search(
      sliceSession: sliceSession,
      measurer: measurer,
      chapter: chapter,
      key: key,
      availableHeight: 20000,
    );

    expect(result.probeCount, 12);
    expect(result.budgetExceeded, isTrue);
    expect(result.fits, isTrue);
    expect(result.measuredHeight, lessThanOrEqualTo(20000.5));
    expect(measurer.probedOffsets, contains(result.slice.endOffset));
  });

  test(
    'checks cancellation after a probe and does not continue searching',
    () async {
      final sliceSession = _sliceSession('abcdefghij');
      final token = NovelReaderPaginationCancellationToken();
      final measurer = _RecordingMeasureSession(
        _linearHeight,
        onMeasure: (_) => token.cancel(),
      );

      await expectLater(
        _search(
          sliceSession: sliceSession,
          measurer: measurer,
          chapter: chapter,
          key: key,
          availableHeight: 50,
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
      expect(measurer.requests, hasLength(1));
    },
  );

  test(
    'reuses the existing measurement cache for identical candidates',
    () async {
      final sliceSession = _sliceSession('abcdefghij');
      final delegate = _RecordingMeasureSession(_linearHeight);
      final cachingSession = NovelReaderCachingPaginationMeasureSession(
        delegate: delegate,
      );

      final first = await _search(
        sliceSession: sliceSession,
        measurer: cachingSession,
        chapter: chapter,
        key: key,
        availableHeight: 45,
      );
      final firstDelegateCallCount = delegate.requests.length;
      final second = await _search(
        sliceSession: sliceSession,
        measurer: cachingSession,
        chapter: chapter,
        key: key,
        availableHeight: 45,
      );

      expect(first.cacheHitCount, 1);
      expect(delegate.requests, hasLength(firstDelegateCallCount));
      expect(second.cacheHitCount, second.probeCount + 1);
      expect(second.slice.endOffset, first.slice.endOffset);
    },
  );

  test('shares in-flight measurements across concurrent searches', () async {
    final sliceSession = _sliceSession('abcdefghij');
    final delegate = _BlockingMeasureSession();
    final cachingSession = NovelReaderCachingPaginationMeasureSession(
      delegate: delegate,
    );

    final firstFuture = _search(
      sliceSession: sliceSession,
      measurer: cachingSession,
      chapter: chapter,
      key: key,
      availableHeight: 45,
    );
    await delegate.firstRequestStarted.future;
    final secondFuture = _search(
      sliceSession: sliceSession,
      measurer: cachingSession,
      chapter: chapter,
      key: key,
      availableHeight: 45,
    );
    await Future<void>.delayed(Duration.zero);

    expect(delegate.requests, hasLength(1));
    delegate.release();
    final results = await Future.wait([firstFuture, secondFuture]);

    expect(results[0].slice.endOffset, results[1].slice.endOffset);
    expect(delegate.requests, hasLength(results[0].probeCount));
    expect(results[1].cacheHitCount, greaterThan(0));
  });

  test('rejects non-monotonic candidate measurements', () async {
    final sliceSession = _sliceSession('abcdefghij');
    final measurer = _RecordingMeasureSession((request) {
      return switch (request.endOffset!) {
        10 => 100,
        5 => 70,
        7 => 60,
        final offset => offset * 10.0,
      };
    });

    await expectLater(
      _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 80,
      ),
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'complexFitSearchNonMonotonic',
        ),
      ),
    );
  });

  test(
    'returns an empty exhausted result without probing an empty atom',
    () async {
      final sliceSession = _sliceSession('');
      final measurer = _RecordingMeasureSession(_linearHeight);

      final result = await _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 100,
      );

      expect(result.slice.startOffset, 0);
      expect(result.slice.endOffset, 0);
      expect(result.slice.hasRenderableContent, isFalse);
      expect(result.exhaustedAtom, isTrue);
      expect(result.probeCount, 0);
      expect(measurer.requests, isEmpty);
    },
  );
}

Future<NovelReaderComplexHtmlFitResult> _search({
  required NovelReaderComplexHtmlSliceSession sliceSession,
  required NovelReaderPaginationMeasureSession measurer,
  required NovelReaderPreparedChapter chapter,
  required NovelReaderPaginationKey key,
  required double availableHeight,
  String bufferedPageHtml = '',
  NovelReaderPaginationCancellationToken? cancellationToken,
}) {
  return const DefaultNovelReaderComplexHtmlFitSearcher()
      .findLargestFittingPrefix(
        session: sliceSession,
        startOffset: 0,
        bufferedPageHtml: bufferedPageHtml,
        availableHeight: availableHeight,
        context: NovelReaderPaginationMeasureContext(
          session: measurer,
          chapter: chapter,
          key: key,
          atomId: 'complex:1',
        ),
        cancellationToken:
            cancellationToken ?? NovelReaderPaginationCancellationToken(),
      );
}

NovelReaderComplexHtmlSliceSession _sliceSession(String text) {
  return const DefaultNovelReaderComplexHtmlBoundaryIndexer().prepare(
    html: '<span>$text</span>',
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'episode-1',
      nodeId: 'node-1',
    ),
  );
}

double _linearHeight(NovelReaderPaginationMeasureRequest request) {
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
    viewportHeightPx: 600,
    typographySignature: 'font=18.5|line=1.6',
    themeSignature: chapter.themeSignature,
    imageDimensionRevision: chapter.imageDimensionRevision,
    rendererRevision: 12,
  );
}

typedef _HeightResolver =
    double Function(NovelReaderPaginationMeasureRequest request);

final class _RecordingMeasureSession
    implements NovelReaderPaginationMeasureSession {
  _RecordingMeasureSession(this.heightResolver, {this.onMeasure});

  final _HeightResolver heightResolver;
  final ValueChanged<NovelReaderPaginationMeasureRequest>? onMeasure;
  final List<NovelReaderPaginationMeasureRequest> requests =
      <NovelReaderPaginationMeasureRequest>[];

  List<int> get probedOffsets =>
      requests.map((request) => request.endOffset!).toList(growable: false);

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    requests.add(request);
    onMeasure?.call(request);
    return NovelReaderPaginationMeasureResult(height: heightResolver(request));
  }

  @override
  Future<void> dispose() async {}
}

final class _BlockingMeasureSession
    implements NovelReaderPaginationMeasureSession {
  final Completer<void> _release = Completer<void>();
  final Completer<void> firstRequestStarted = Completer<void>();
  final List<NovelReaderPaginationMeasureRequest> requests =
      <NovelReaderPaginationMeasureRequest>[];

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    requests.add(request);
    if (!firstRequestStarted.isCompleted) {
      firstRequestStarted.complete();
    }
    await _release.future;
    await Future<void>.delayed(Duration.zero);
    return NovelReaderPaginationMeasureResult(height: _linearHeight(request));
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
