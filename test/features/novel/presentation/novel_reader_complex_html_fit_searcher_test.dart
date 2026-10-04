import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_fit_searcher.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  late NovelReaderPreparedChapter chapter;
  late NovelReaderPaginationKey key;

  setUp(() {
    chapter = _chapter();
    key = _key(chapter);
  });

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

  test(
    'maps a pure invalid-height failure to the Host recovery contract',
    () async {
      final measurer = _RecordingMeasureSession((_) => double.nan);
      await expectLater(
        _search(
          sliceSession: _sliceSession('abc'),
          measurer: measurer,
          chapter: chapter,
          key: key,
          availableHeight: 100,
        ),
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (error) => error.code,
            'code',
            'complexFitSearchInvalidMeasurement',
          ),
        ),
      );
      expect(measurer.requests, hasLength(1));
    },
  );

  test(
    'preserves Host measurement context, errors and canonical projection',
    () async {
      const text = 'e\u0301  中';
      const buffer = '<p>kept buffer</p>';
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
      final sliceSession = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
          .prepare(
            html: '<span>$text</span>',
            startAnchor: anchor,
            sourceAnchorProjection: NovelReaderSourceAnchorProjection(
              baseAnchor: anchor,
              semanticOffsetsBySourceRuneBoundary: const [7, 8, 9, 10, 10, 11],
            ),
          );
      final measurer = _RecordingMeasureSession((_) => 40);
      final result = await _search(
        sliceSession: sliceSession,
        measurer: measurer,
        chapter: chapter,
        key: key,
        availableHeight: 100,
        bufferedPageHtml: buffer,
      );
      expect(measurer.requests, hasLength(1));
      final request = measurer.requests.single;
      expect(request.chapter, same(chapter));
      expect(request.key, same(key));
      expect(request.atomId, 'complex:1');
      expect(request.html, '$buffer<span>$text</span>');
      expect(request.startOffset, 0);
      expect(request.endOffset, 4);
      // Measurement ranges remain local graphemes; only the returned slice
      // acquires the reader's folded-whitespace semantic anchor coordinates.
      expect(result.slice.html, '<span>$text</span>');
      expect(result.slice.sourceRuneLength, 5);
      expect(result.slice.startAnchor.textOffset, 7);
      expect(result.slice.endAnchor.textOffset, 11);
      for (final projected in [
        result.slice.startAnchor,
        result.slice.endAnchor,
      ]) {
        expect(projected.episodeId, anchor.episodeId);
        expect(projected.nodeId, anchor.nodeId);
        expect(projected.formatVersion, anchor.formatVersion);
        expect(projected.textIdentity, anchor.textIdentity);
      }

      final sentinel = StateError('Host measurement failure');
      final failing = _RecordingMeasureSession((_) => throw sentinel);
      await expectLater(
        _search(
          sliceSession: sliceSession,
          measurer: failing,
          chapter: chapter,
          key: key,
          availableHeight: 100,
          bufferedPageHtml: buffer,
        ),
        throwsA(same(sentinel)),
      );
      expect(failing.requests, hasLength(1));
      expect(failing.requests.single.chapter, same(chapter));
      expect(failing.requests.single.key, same(key));
      expect(failing.requests.single.atomId, request.atomId);
      expect(failing.requests.single.html, request.html);
      expect(failing.requests.single.startOffset, request.startOffset);
      expect(failing.requests.single.endOffset, request.endOffset);
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
        cancellationToken: NovelReaderPaginationCancellationToken(),
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
  _RecordingMeasureSession(this.heightResolver);

  final _HeightResolver heightResolver;
  final List<NovelReaderPaginationMeasureRequest> requests =
      <NovelReaderPaginationMeasureRequest>[];

  List<int> get probedOffsets =>
      requests.map((request) => request.endOffset!).toList(growable: false);

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
