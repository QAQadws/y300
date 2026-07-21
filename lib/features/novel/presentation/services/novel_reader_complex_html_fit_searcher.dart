import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

final class NovelReaderPaginationMeasureContext {
  const NovelReaderPaginationMeasureContext({
    required this.session,
    required this.chapter,
    required this.key,
    required this.atomId,
  });

  final NovelReaderPaginationMeasureSession session;
  final NovelReaderPreparedChapter chapter;
  final NovelReaderPaginationKey key;
  final String atomId;
}

abstract interface class NovelReaderComplexHtmlFitSearcher {
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
  });
}

final class DefaultNovelReaderComplexHtmlFitSearcher
    implements NovelReaderComplexHtmlFitSearcher {
  const DefaultNovelReaderComplexHtmlFitSearcher({
    this.maxProbeCount = 12,
    this.fitTolerance = 0.5,
    this.monotonicityTolerance = 0.5,
  }) : assert(maxProbeCount >= 4),
       assert(fitTolerance >= 0),
       assert(monotonicityTolerance >= 0);

  final int maxProbeCount;
  final double fitTolerance;
  final double monotonicityTolerance;

  @override
  Future<NovelReaderComplexHtmlFitResult> findLargestFittingPrefix({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
    required NovelReaderPaginationCancellationToken cancellationToken,
  }) async {
    _validateInput(
      session: session,
      startOffset: startOffset,
      availableHeight: availableHeight,
      context: context,
    );
    cancellationToken.throwIfCancelled();

    final boundaries = _candidateBoundaries(session, startOffset);
    if (boundaries.isEmpty) {
      final emptySlice = session.slice(
        startOffset: startOffset,
        endOffset: startOffset,
      );
      return NovelReaderComplexHtmlFitResult(
        slice: emptySlice,
        measuredHeight: 0,
        probeCount: 0,
        cacheHitCount: 0,
        fits: true,
        exhaustedAtom: true,
        requiresFreshPage: false,
        budgetExceeded: false,
      );
    }

    final state = _FitSearchState(
      context: context,
      cancellationToken: cancellationToken,
      availableHeight: availableHeight,
      maxProbeCount: maxProbeCount,
      fitTolerance: fitTolerance,
      monotonicityTolerance: monotonicityTolerance,
    );
    return _searchAttempt(
      session: session,
      startOffset: startOffset,
      bufferedPageHtml: bufferedPageHtml,
      boundaries: boundaries,
      state: state,
      requiresFreshPage: false,
    );
  }

  Future<NovelReaderComplexHtmlFitResult> _searchAttempt({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required List<NovelReaderComplexHtmlBoundary> boundaries,
    required _FitSearchState state,
    required bool requiresFreshPage,
  }) async {
    final observations = <int, _FitObservation>{};

    Future<_FitObservation?> probeIndex(int index) async {
      final existing = observations[index];
      if (existing != null) {
        return existing;
      }
      final boundary = boundaries[index];
      final slice = session.slice(
        startOffset: startOffset,
        endOffset: boundary.textOffset,
      );
      final observation = await state.probe(
        bufferedPageHtml: bufferedPageHtml,
        slice: slice,
      );
      if (observation != null) {
        observations[index] = observation;
      }
      return observation;
    }

    final lastIndex = boundaries.length - 1;
    final whole = await probeIndex(lastIndex);
    if (whole == null) {
      throw const NovelReaderPaginationException(
        code: 'complexFitSearchBudgetUnavailable',
        message: 'No complex HTML candidate could be measured.',
      );
    }
    if (whole.fits) {
      return _result(
        observation: whole,
        session: session,
        state: state,
        requiresFreshPage: requiresFreshPage,
      );
    }

    final minimum = await probeIndex(0);
    if (minimum == null) {
      return _result(
        observation: whole,
        session: session,
        state: state,
        requiresFreshPage: requiresFreshPage,
      );
    }
    if (!minimum.fits) {
      if (!requiresFreshPage && bufferedPageHtml.isNotEmpty) {
        return _searchAttempt(
          session: session,
          startOffset: startOffset,
          bufferedPageHtml: '',
          boundaries: boundaries,
          state: state,
          requiresFreshPage: true,
        );
      }
      return _result(
        observation: minimum,
        session: session,
        state: state,
        requiresFreshPage: requiresFreshPage,
      );
    }

    var bestFitIndex = 0;
    var firstOverflowIndex = lastIndex;
    final coarseIndices = <int>[
      for (var index = 1; index < lastIndex; index += 1)
        if (_isCoarseBoundary(boundaries[index])) index,
    ];

    // Search semantic boundaries first, then refine only the remaining
    // grapheme interval. This preserves an upper-bound result without paying
    // renderer probes for every fine candidate.
    var coarseLow = -1;
    var coarseHigh = coarseIndices.length;
    while (coarseHigh - coarseLow > 1 && !state.budgetExceeded) {
      final middle = coarseLow + ((coarseHigh - coarseLow) ~/ 2);
      final index = coarseIndices[middle];
      final observation = await probeIndex(index);
      if (observation == null) {
        break;
      }
      if (observation.fits) {
        bestFitIndex = index;
        coarseLow = middle;
      } else {
        firstOverflowIndex = index;
        coarseHigh = middle;
      }
    }

    var fineLow = bestFitIndex;
    var fineHigh = firstOverflowIndex;
    while (fineHigh - fineLow > 1 && !state.budgetExceeded) {
      final middle = fineLow + ((fineHigh - fineLow) ~/ 2);
      final observation = await probeIndex(middle);
      if (observation == null) {
        break;
      }
      if (observation.fits) {
        bestFitIndex = middle;
        fineLow = middle;
      } else {
        fineHigh = middle;
      }
    }

    return _result(
      observation: observations[bestFitIndex]!,
      session: session,
      state: state,
      requiresFreshPage: requiresFreshPage,
    );
  }

  NovelReaderComplexHtmlFitResult _result({
    required _FitObservation observation,
    required NovelReaderComplexHtmlSliceSession session,
    required _FitSearchState state,
    required bool requiresFreshPage,
  }) {
    return NovelReaderComplexHtmlFitResult(
      slice: observation.slice,
      measuredHeight: observation.height,
      probeCount: state.probeCount,
      cacheHitCount: state.cacheHitCount,
      fits: observation.fits,
      exhaustedAtom: observation.slice.endOffset == session.textLength,
      requiresFreshPage: requiresFreshPage,
      budgetExceeded: state.budgetExceeded,
    );
  }

  List<NovelReaderComplexHtmlBoundary> _candidateBoundaries(
    NovelReaderComplexHtmlSliceSession session,
    int startOffset,
  ) {
    final byOffset = <int, NovelReaderComplexHtmlBoundary>{};
    for (final boundary in session.boundaries) {
      if (boundary.textOffset <= startOffset ||
          boundary.textOffset > session.textLength ||
          !session.isLegalBoundary(boundary.textOffset)) {
        continue;
      }
      final previous = byOffset[boundary.textOffset];
      if (previous == null || boundary.preference > previous.preference) {
        byOffset[boundary.textOffset] = boundary;
      }
    }
    final result = byOffset.values.toList()
      ..sort((left, right) => left.textOffset.compareTo(right.textOffset));
    if (startOffset < session.textLength &&
        (result.isEmpty || result.last.textOffset != session.textLength)) {
      throw const NovelReaderPaginationException(
        code: 'complexFitSearchMissingAtomEnd',
        message: 'The complex HTML session has no legal atom-end boundary.',
      );
    }
    return result;
  }

  bool _isCoarseBoundary(NovelReaderComplexHtmlBoundary boundary) {
    return boundary.kind != NovelReaderComplexBoundaryKind.graphemeEnd;
  }

  void _validateInput({
    required NovelReaderComplexHtmlSliceSession session,
    required int startOffset,
    required double availableHeight,
    required NovelReaderPaginationMeasureContext context,
  }) {
    if (startOffset < 0 ||
        startOffset > session.textLength ||
        !session.isLegalBoundary(startOffset)) {
      throw ArgumentError.value(
        startOffset,
        'startOffset',
        'Must be a legal complex HTML boundary.',
      );
    }
    if (!availableHeight.isFinite || availableHeight <= 0) {
      throw ArgumentError.value(
        availableHeight,
        'availableHeight',
        'Must be finite and positive.',
      );
    }
    if (context.chapter.episodeId != context.key.episodeId) {
      throw ArgumentError(
        'The pagination measure context chapter and key do not match.',
      );
    }
  }
}

final class _FitSearchState {
  _FitSearchState({
    required this.context,
    required this.cancellationToken,
    required this.availableHeight,
    required this.maxProbeCount,
    required this.fitTolerance,
    required this.monotonicityTolerance,
  });

  final NovelReaderPaginationMeasureContext context;
  final NovelReaderPaginationCancellationToken cancellationToken;
  final double availableHeight;
  final int maxProbeCount;
  final double fitTolerance;
  final double monotonicityTolerance;
  final Map<_FitCandidateKey, _FitObservation> _cache =
      <_FitCandidateKey, _FitObservation>{};
  final Map<String, _MonotonicProbeLedger> _ledgers =
      <String, _MonotonicProbeLedger>{};

  int probeCount = 0;
  int cacheHitCount = 0;
  bool budgetExceeded = false;

  Future<_FitObservation?> probe({
    required String bufferedPageHtml,
    required NovelReaderComplexHtmlSlice slice,
  }) async {
    cancellationToken.throwIfCancelled();
    final candidateHtml = '$bufferedPageHtml${slice.html}';
    final key = _FitCandidateKey(
      html: candidateHtml,
      startOffset: slice.startOffset,
      endOffset: slice.endOffset,
    );
    final cached = _cache[key];
    if (cached != null) {
      cacheHitCount += 1;
      cancellationToken.throwIfCancelled();
      return cached;
    }
    if (probeCount >= maxProbeCount) {
      budgetExceeded = true;
      return null;
    }

    probeCount += 1;
    final measured = await context.session.measure(
      NovelReaderPaginationMeasureRequest(
        html: candidateHtml,
        chapter: context.chapter,
        key: context.key,
        atomId: context.atomId,
        startOffset: slice.startOffset,
        endOffset: slice.endOffset,
      ),
    );
    cancellationToken.throwIfCancelled();
    if (!measured.height.isFinite || measured.height < 0) {
      throw const NovelReaderPaginationException(
        code: 'complexFitSearchInvalidMeasurement',
        message: 'Complex HTML measurement must be finite and non-negative.',
      );
    }
    if (measured.fromCache) {
      cacheHitCount += 1;
    }
    final observation = _FitObservation(
      slice: slice,
      height: measured.height,
      fits: measured.height <= availableHeight + fitTolerance,
    );
    final ledger = _ledgers.putIfAbsent(
      bufferedPageHtml,
      () => _MonotonicProbeLedger(tolerance: monotonicityTolerance),
    );
    ledger.record(observation);
    _cache[key] = observation;
    return observation;
  }
}

final class _MonotonicProbeLedger {
  _MonotonicProbeLedger({required this.tolerance});

  final double tolerance;
  final Map<int, _FitObservation> _observations = <int, _FitObservation>{};

  void record(_FitObservation candidate) {
    for (final observation in _observations.values) {
      final candidateIsLater =
          candidate.slice.endOffset > observation.slice.endOffset;
      final candidateIsEarlier =
          candidate.slice.endOffset < observation.slice.endOffset;
      final heightDecreases =
          candidateIsLater && candidate.height + tolerance < observation.height;
      final previousHeightDecreases =
          candidateIsEarlier &&
          observation.height + tolerance < candidate.height;
      final fitContradiction =
          (candidateIsLater && candidate.fits && !observation.fits) ||
          (candidateIsEarlier && !candidate.fits && observation.fits);
      if (heightDecreases || previousHeightDecreases || fitContradiction) {
        throw const NovelReaderPaginationException(
          code: 'complexFitSearchNonMonotonic',
          message: 'Complex HTML candidate measurements are not monotonic.',
        );
      }
    }
    _observations[candidate.slice.endOffset] = candidate;
  }
}

final class _FitObservation {
  const _FitObservation({
    required this.slice,
    required this.height,
    required this.fits,
  });

  final NovelReaderComplexHtmlSlice slice;
  final double height;
  final bool fits;
}

final class _FitCandidateKey {
  const _FitCandidateKey({
    required this.html,
    required this.startOffset,
    required this.endOffset,
  });

  final String html;
  final int startOffset;
  final int endOffset;

  @override
  bool operator ==(Object other) {
    return other is _FitCandidateKey &&
        other.html == html &&
        other.startOffset == startOffset &&
        other.endOffset == endOffset;
  }

  @override
  int get hashCode => Object.hash(html, startOffset, endOffset);
}
