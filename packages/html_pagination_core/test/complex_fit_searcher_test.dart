import 'dart:async';

import 'package:test/test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html_pagination_core/html_pagination_core.dart';

void main() {
  test('whole remainder fast check accepts an exact full fit', () async {
    final sliceSession = _sliceSession('abcde');
    final measurer = _RecordingMeasureSession(_linearHeight);

    final result = await _search(
      sliceSession: sliceSession,
      measurer: measurer,
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
      final fragmentHeight = (request.endOffset - request.startOffset) * 10.0;
      return request.html.startsWith('<p>buffer</p>')
          ? fragmentHeight + 100
          : fragmentHeight;
    });

    final result = await _search(
      sliceSession: sliceSession,
      measurer: measurer,
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

  test('caps expansion independently of total atom length', () async {
    final sliceSession = _sliceSession(List.filled(4096, 'a').join());
    final measurer = _RecordingMeasureSession(_linearHeight);

    final result = await _search(
      sliceSession: sliceSession,
      measurer: measurer,
      availableHeight: 20000,
    );

    expect(result.probeCount, lessThanOrEqualTo(12));
    expect(measurer.probedOffsets.first, 64);
    expect(measurer.probedOffsets.every((offset) => offset <= 1024), isTrue);
    expect(result.slice.endOffset, 1024);
    expect(result.budgetExceeded, isTrue);
    expect(result.fits, isTrue);
    expect(result.measuredHeight, lessThanOrEqualTo(20000.5));
    expect(measurer.probedOffsets, contains(result.slice.endOffset));
  });

  test(
    'expansion advances across a protected gap without repeat probes',
    () async {
      final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
        html: '<p>A<ruby>${'字' * 200}<rt>reading</rt></ruby>B</p>',
      );
      final measurer = _RecordingMeasureSession(_linearHeight);
      final result = await _search(
        sliceSession: session,
        measurer: measurer,
        availableHeight: 10,
      );
      expect(result.slice.endOffset, 1);
      expect(result.fits, isTrue);
      expect(measurer.requests, hasLength(2));
      expect(measurer.probedOffsets.toSet(), hasLength(2));
      expect(measurer.probedOffsets.last, greaterThan(200));
      final tailMeasurer = _RecordingMeasureSession(_linearHeight);
      final tail = await _search(
        sliceSession: session,
        measurer: tailMeasurer,
        startOffset: result.slice.endOffset,
        availableHeight: 3000,
      );
      expect(tail.exhaustedAtom, isTrue);
      expect(tailMeasurer.requests.length, lessThanOrEqualTo(12));
      expect(tail.slice.html, contains('<rt>reading</rt>'));
      expect(
        html_parser
            .parseFragment('${result.slice.html}${tail.slice.html}')
            .text,
        'A${'字' * 200}readingB',
      );
    },
  );

  test(
    'uses the last verified page capacity only as a measured hint',
    () async {
      final measurer = _RecordingMeasureSession(_linearHeight);
      final result = await _search(
        sliceSession: _sliceSession('a' * 300),
        measurer: measurer,
        availableHeight: 200,
        preferredWindowGraphemes: 20,
      );
      expect(measurer.probedOffsets.first, 20);
      expect(result.slice.endOffset, 20);
      expect(measurer.probedOffsets, contains(40));
    },
  );

  test(
    'combined HTML and node limits shrink to a verified legal prefix',
    () async {
      final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
        html: '<div>${List.filled(200, '<span>中</span>').join()}</div>',
      );
      const buffer = '<p>buffer</p>';
      final measurer = _RecordingMeasureSession((_) => 10);
      final result = await _search(
        sliceSession: session,
        measurer: measurer,
        availableHeight: 100,
        bufferedPageHtml: buffer,
        budget: const HtmlComplexSearchBudget(
          maxCandidateHtmlCodeUnits: 160,
          maxCandidateDomNodes: 12,
        ),
      );
      expect(result.fits, isTrue);
      expect(result.budgetExceeded, isTrue);
      expect(result.requiresFreshPage, isFalse);
      expect(measurer.requests, isNotEmpty);
      for (final request in measurer.requests) {
        expect(request.html, startsWith(buffer));
        expect(request.html.length, lessThanOrEqualTo(160));
        expect(
          HtmlComplexSearchBudget.countDomNodes(request.html),
          lessThanOrEqualTo(12),
        );
      }
    },
  );

  test(
    'four probes reserve a fresh-page minimum even with overflowing buffer',
    () async {
      final measurer = _RecordingMeasureSession(
        (request) => request.html.startsWith('<p>buffer</p>')
            ? 1000
            : _linearHeight(request),
      );
      final result = await _search(
        sliceSession: _sliceSession('a' * 100),
        measurer: measurer,
        availableHeight: 15,
        bufferedPageHtml: '<p>buffer</p>',
        budget: const HtmlComplexSearchBudget(maxProbeCount: 4),
      );
      expect(result.requiresFreshPage, isTrue);
      expect(result.fits, isTrue);
      expect(result.slice.endOffset, 1);
      expect(result.probeCount, lessThanOrEqualTo(4));
      expect(
        measurer.requests.any(
          (r) => !r.html.startsWith('<p>buffer</p>') && r.endOffset == 1,
        ),
        isTrue,
      );
    },
  );

  test(
    'finite oversized ruby minimum is measured fresh without splitting',
    () async {
      final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
        html: '<ruby>${'文' * 2000}<rt>reading</rt></ruby>',
      );
      final measurer = _RecordingMeasureSession((_) => 500);
      final result = await _search(
        sliceSession: session,
        measurer: measurer,
        availableHeight: 100,
        bufferedPageHtml: '<p>buffer</p>',
      );
      expect(result.oversizedMinimumFragment, isTrue);
      expect(result.requiresFreshPage, isTrue);
      expect(result.fits, isFalse);
      expect(result.slice.endOffset, session.textLength);
      expect(result.slice.html, contains('<rt>reading</rt>'));
      expect(measurer.requests, hasLength(1));
      expect(measurer.requests.single.html, isNot(startsWith('<p>buffer</p>')));
    },
  );

  test(
    'unmeasurable indivisible minimum is recoverable with zero probes',
    () async {
      final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
        html: '<ruby>${'文' * 33000}<rt>reading</rt></ruby>',
      );
      final measurer = _RecordingMeasureSession((_) => 10);
      await expectLater(
        _search(
          sliceSession: session,
          measurer: measurer,
          availableHeight: 100,
        ),
        throwsA(
          isA<HtmlPaginationException>().having(
            (e) => e.code,
            'code',
            'complexFitSearchCandidateLimitExceeded',
          ),
        ),
      );
      expect(measurer.requests, isEmpty);
    },
  );

  test(
    'checks cancellation after a probe and does not continue searching',
    () async {
      final sliceSession = _sliceSession('abcdefghij');
      final token = _Cancellation();
      final measurer = _RecordingMeasureSession(
        _linearHeight,
        onMeasure: (_) => token.cancel(),
      );

      await expectLater(
        _search(
          sliceSession: sliceSession,
          measurer: measurer,
          availableHeight: 50,
          cancellationToken: token,
        ),
        throwsA(
          isA<HtmlPaginationException>().having(
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
    'cancellation releases a pending probe and observes its late success',
    () async {
      final token = _Cancellation();
      final measurer = _BlockingMeasureSession();
      final pending = _search(
        sliceSession: _sliceSession('abc'),
        measurer: measurer,
        availableHeight: 100,
        cancellationToken: token,
      );
      await measurer.firstRequestStarted.future;
      final cancelled = expectLater(
        pending,
        throwsA(
          isA<HtmlPaginationException>().having(
            (e) => e.code,
            'code',
            'paginationCancelled',
          ),
        ),
      );
      token.cancel();
      await cancelled;
      expect(measurer.requests, hasLength(1));
      measurer.release();
      await Future<void>.delayed(Duration.zero);
      expect(measurer.requests, hasLength(1));
    },
  );

  test('rejects non-monotonic candidate measurements', () async {
    final sliceSession = _sliceSession('abcdefghij');
    final measurer = _RecordingMeasureSession((request) {
      return switch (request.endOffset) {
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
        availableHeight: 80,
      ),
      throwsA(
        isA<HtmlPaginationException>().having(
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

Future<HtmlComplexFitResult> _search({
  required HtmlComplexSliceSession sliceSession,
  required _MeasureSession measurer,
  required double availableHeight,
  String bufferedPageHtml = '',
  _Cancellation? cancellationToken,
  int startOffset = 0,
  HtmlComplexSearchBudget budget = const HtmlComplexSearchBudget(),
  int? preferredWindowGraphemes,
}) {
  return DefaultHtmlComplexFitSearcher(budget: budget).findLargestFittingPrefix(
    session: sliceSession,
    startOffset: startOffset,
    bufferedPageHtml: bufferedPageHtml,
    availableHeight: availableHeight,
    measure: measurer.measure,
    cancellationToken: cancellationToken ?? _Cancellation(),
    preferredWindowGraphemes: preferredWindowGraphemes,
  );
}

HtmlComplexSliceSession _sliceSession(String text) {
  return const DefaultHtmlComplexBoundaryIndexer().prepare(
    html: '<span>$text</span>',
  );
}

double _linearHeight(HtmlPaginationMeasureCandidate request) {
  return (request.endOffset - request.startOffset) * 10.0;
}

abstract interface class _MeasureSession {
  Future<HtmlPaginationMeasurement> measure(
    HtmlPaginationMeasureCandidate request,
  );
}

typedef _HeightResolver =
    double Function(HtmlPaginationMeasureCandidate request);

final class _RecordingMeasureSession implements _MeasureSession {
  _RecordingMeasureSession(this.heightResolver, {this.onMeasure});

  final _HeightResolver heightResolver;
  final void Function(HtmlPaginationMeasureCandidate)? onMeasure;
  final requests = <HtmlPaginationMeasureCandidate>[];

  List<int> get probedOffsets =>
      requests.map((request) => request.endOffset).toList(growable: false);

  @override
  Future<HtmlPaginationMeasurement> measure(
    HtmlPaginationMeasureCandidate request,
  ) async {
    requests.add(request);
    onMeasure?.call(request);
    return HtmlPaginationMeasurement(height: heightResolver(request));
  }
}

final class _BlockingMeasureSession implements _MeasureSession {
  final _release = Completer<void>();
  final firstRequestStarted = Completer<void>();
  final requests = <HtmlPaginationMeasureCandidate>[];

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<HtmlPaginationMeasurement> measure(
    HtmlPaginationMeasureCandidate request,
  ) async {
    requests.add(request);
    if (!firstRequestStarted.isCompleted) {
      firstRequestStarted.complete();
    }
    await _release.future;
    await Future<void>.delayed(Duration.zero);
    return HtmlPaginationMeasurement(height: _linearHeight(request));
  }
}

/// Only supplies the neutral port needed by these deterministic fit tests.
/// Reader request identity and the production token remain in the App tests.
final class _Cancellation implements HtmlPaginationCancellation {
  final _cancelled = Completer<void>();

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  void throwIfCancelled() {
    if (_cancelled.isCompleted) {
      throw const HtmlPaginationException(
        code: 'paginationCancelled',
        message: 'The test request was cancelled.',
      );
    }
  }

  @override
  Future<T> waitFor<T>(Future<T> operation) {
    return Future.any<T>([
      operation,
      _cancelled.future.then<T>((_) {
        throwIfCancelled();
        throw StateError('Cancellation must stop this wait.');
      }),
    ]);
  }

  @override
  Future<void> yieldToEventLoop() async {
    throwIfCancelled();
    await waitFor(Future<void>.delayed(Duration.zero));
    throwIfCancelled();
  }
}
