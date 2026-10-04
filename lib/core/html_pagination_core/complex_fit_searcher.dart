import 'dart:math' as math;

import 'complex_fit.dart';
import 'complex_slice.dart';
import 'complex_search_budget.dart';
import 'ports.dart';
import 'work_slice.dart';

abstract interface class HtmlComplexFitSearcher {
  /// Returns a verified legal prefix within the search budget, not a globally
  /// optimal boundary for arbitrary non-monotonic HTML layout.
  Future<HtmlComplexFitResult> findLargestFittingPrefix({
    required HtmlComplexSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required HtmlPaginationMeasure measure,
    required HtmlPaginationCancellation cancellationToken,
    int? preferredWindowGraphemes,
  });
}

final class DefaultHtmlComplexFitSearcher implements HtmlComplexFitSearcher {
  const DefaultHtmlComplexFitSearcher({
    this.budget = const HtmlComplexSearchBudget(),
    this.fitTolerance = 0.5,
    this.monotonicityTolerance = 0.5,
  }) : assert(fitTolerance >= 0),
       assert(monotonicityTolerance >= 0);

  final HtmlComplexSearchBudget budget;
  final double fitTolerance;
  final double monotonicityTolerance;

  @override
  Future<HtmlComplexFitResult> findLargestFittingPrefix({
    required HtmlComplexSliceSession session,
    required int startOffset,
    required String bufferedPageHtml,
    required double availableHeight,
    required HtmlPaginationMeasure measure,
    required HtmlPaginationCancellation cancellationToken,
    int? preferredWindowGraphemes,
  }) async {
    if (startOffset < 0 ||
        startOffset > session.textLength ||
        !session.isLegalBoundary(startOffset)) {
      throw ArgumentError.value(startOffset, 'startOffset', 'Must be legal.');
    }
    if (!availableHeight.isFinite || availableHeight <= 0) {
      throw ArgumentError.value(availableHeight, 'availableHeight');
    }
    cancellationToken.throwIfCancelled();
    final first = session.firstBoundaryIndexAfter(startOffset);
    if (startOffset == session.textLength) {
      return HtmlComplexFitResult(
        slice: session.slice(startOffset: startOffset, endOffset: startOffset),
        measuredHeight: 0,
        probeCount: 0,
        cacheHitCount: 0,
        fits: true,
        exhaustedAtom: true,
        requiresFreshPage: false,
        budgetExceeded: false,
      );
    }
    if (first == session.boundaries.length ||
        session.boundaries.last.textOffset != session.textLength) {
      throw const HtmlPaginationException(
        code: 'complexFitSearchMissingAtomEnd',
        message: 'The complex HTML session has no legal atom-end boundary.',
      );
    }

    final state = _FitSearchState(
      measure: measure,
      cancellationToken: cancellationToken,
      availableHeight: availableHeight,
      budget: budget,
      fitTolerance: fitTolerance,
      monotonicityTolerance: monotonicityTolerance,
    );
    final window = (preferredWindowGraphemes ?? budget.initialWindowGraphemes)
        .clamp(1, budget.maxWindowGraphemes);
    return _searchAttempt(
      session: session,
      startOffset: startOffset,
      first: first,
      bufferedPageHtml: bufferedPageHtml,
      state: state,
      window: window,
      requiresFreshPage: false,
    );
  }

  Future<HtmlComplexFitResult> _searchAttempt({
    required HtmlComplexSliceSession session,
    required int startOffset,
    required int first,
    required String bufferedPageHtml,
    required _FitSearchState state,
    required int window,
    required bool requiresFreshPage,
  }) async {
    final boundaries = session.boundaries;
    if (bufferedPageHtml.length > budget.maxCandidateHtmlCodeUnits) {
      state.budgetExceeded = true;
      return _searchAttempt(
        session: session,
        startOffset: startOffset,
        first: first,
        bufferedPageHtml: '',
        state: state,
        window: window,
        requiresFreshPage: true,
      );
    }
    // Reuse the immutable index. No suffix filter/copy/sort on every page.
    int floorBoundary(int offset) =>
        math.max(first, session.firstBoundaryIndexAfter(offset) - 1);
    final windowEnd = math.min(
      session.textLength,
      startOffset + budget.maxWindowGraphemes,
    );
    final last = floorBoundary(windowEnd);
    final seed = math.min(
      last,
      floorBoundary(math.min(session.textLength, startOffset + window)),
    );
    final bufferNodes = bufferedPageHtml.isEmpty
        ? 0
        : HtmlComplexSearchBudget.countDomNodes(bufferedPageHtml);
    final observations = <int, _FitObservation>{};
    final reserveFreshProbe = bufferedPageHtml.isNotEmpty;

    Future<_FitObservation?> probe(int index) async {
      await state.workSlice.yieldIfNeeded();
      final existing = observations[index];
      if (existing != null) return existing;
      final slice = session.slice(
        startOffset: startOffset,
        endOffset: boundaries[index].textOffset,
      );
      final isMinimum = index == first;
      final candidate = '$bufferedPageHtml${slice.html}';
      // Buffer and slice are separate DOM fragments. Their summed node count
      // is a conservative bound if adjacent text nodes merge during parsing.
      final nodeCount = bufferNodes + slice.domNodeCount;
      final outsideWindow = slice.endOffset > windowEnd;
      final ordinary =
          !outsideWindow && budget.allowsCandidate(candidate, nodeCount);
      final exceptional =
          !ordinary &&
          isMinimum &&
          bufferedPageHtml.isEmpty &&
          budget.allowsCandidate(candidate, nodeCount, oversizedMinimum: true);
      if (!ordinary && !exceptional) {
        state.budgetExceeded = true;
        return null;
      }
      final observation = await state.probe(
        bufferedPageHtml: bufferedPageHtml,
        slice: slice,
        oversizedMinimum: exceptional,
        probeLimit: budget.maxProbeCount - (reserveFreshProbe ? 1 : 0),
      );
      if (observation != null) observations[index] = observation;
      return observation;
    }

    Future<HtmlComplexFitResult> retryFresh() => _searchAttempt(
      session: session,
      startOffset: startOffset,
      first: first,
      bufferedPageHtml: '',
      state: state,
      window: window,
      requiresFreshPage: true,
    );

    // On the fresh retry, measure the minimum first with the reserved probe.
    // Ordinary fresh/short atoms retain the one-probe whole-fit path.
    _FitObservation? minimum;
    if (requiresFreshPage) {
      minimum = await probe(first);
      if (minimum == null) _throwUnavailable(state);
      if (!minimum.fits) return _result(minimum, session, state, '', true);
    }
    var candidate = await probe(seed);
    if (candidate == null || !candidate.fits) {
      minimum ??= await probe(first);
      if (minimum == null) {
        if (bufferedPageHtml.isNotEmpty) return retryFresh();
        _throwUnavailable(state);
      }
      if (!minimum.fits) {
        if (bufferedPageHtml.isNotEmpty) return retryFresh();
        return _result(
          minimum,
          session,
          state,
          bufferedPageHtml,
          requiresFreshPage,
        );
      }
    }

    var bestIndex = candidate?.fits == true ? seed : first;
    var best = candidate?.fits == true ? candidate! : minimum!;
    var upper = seed;
    if (candidate?.fits == true) {
      // Expand only around a page-sized hint, never to the whole long suffix.
      while (bestIndex < last && state.hasProbeRoom(reserveFreshProbe)) {
        final span = boundaries[bestIndex].textOffset - startOffset;
        // A doubled offset may still lie inside the same protected cluster.
        // Always advance to another legal index, including on cache hits.
        final next = math.min(
          last,
          math.max(
            bestIndex + 1,
            floorBoundary(
              math.min(windowEnd, startOffset + math.max(span + 1, span * 2)),
            ),
          ),
        );
        upper = next;
        candidate = await probe(next);
        if (candidate == null || !candidate.fits) break;
        bestIndex = next;
        best = candidate;
      }
      if (bestIndex == last && best.slice.endOffset < session.textLength) {
        state.budgetExceeded = true;
      }
    }

    // Semantic pivots first, then fine legal boundaries in the bounded bracket.
    while (upper - bestIndex > 1 && state.hasProbeRoom(reserveFreshProbe)) {
      final middle = _semanticMiddle(boundaries, bestIndex, upper);
      candidate = await probe(middle);
      if (candidate?.fits == true) {
        bestIndex = middle;
        best = candidate!;
      } else {
        upper = middle;
      }
    }
    if (!state.hasProbeRoom(reserveFreshProbe) &&
        (upper > bestIndex || bestIndex < last)) {
      state.budgetExceeded = true;
    }
    return _result(best, session, state, bufferedPageHtml, requiresFreshPage);
  }

  int _semanticMiddle(List<HtmlComplexBoundary> boundaries, int low, int high) {
    final middle = low + ((high - low) ~/ 2);
    for (var distance = 0; distance < high - low; distance += 1) {
      final left = middle - distance;
      if (left > low &&
          boundaries[left].kind != HtmlComplexBoundaryKind.graphemeEnd) {
        return left;
      }
      final right = middle + distance;
      if (right < high &&
          boundaries[right].kind != HtmlComplexBoundaryKind.graphemeEnd) {
        return right;
      }
    }
    return middle;
  }

  Never _throwUnavailable(_FitSearchState state) {
    throw HtmlPaginationException(
      code: state.probeCount >= budget.maxProbeCount
          ? 'complexFitSearchBudgetUnavailable'
          : 'complexFitSearchCandidateLimitExceeded',
      message: 'No safely bounded complex HTML minimum could be measured.',
    );
  }

  HtmlComplexFitResult _result(
    _FitObservation observation,
    HtmlComplexSliceSession session,
    _FitSearchState state,
    String buffer,
    bool requiresFreshPage,
  ) {
    final accepted = state.verifyAccepted(buffer, observation);
    return HtmlComplexFitResult(
      slice: accepted.slice,
      measuredHeight: accepted.height,
      probeCount: state.probeCount,
      cacheHitCount: state.cacheHitCount,
      fits: accepted.fits,
      exhaustedAtom: accepted.slice.endOffset == session.textLength,
      requiresFreshPage: requiresFreshPage,
      budgetExceeded: state.budgetExceeded,
      oversizedMinimumFragment: accepted.oversizedMinimum,
    );
  }
}

final class _FitSearchState {
  _FitSearchState({
    required this.measure,
    required this.cancellationToken,
    required this.availableHeight,
    required this.budget,
    required this.fitTolerance,
    required this.monotonicityTolerance,
  }) : workSlice = HtmlPaginationWorkSlice(
         budget: budget.workSliceDuration,
         cancellationToken: cancellationToken,
       );

  final HtmlPaginationMeasure measure;
  final HtmlPaginationCancellation cancellationToken;
  final double availableHeight;
  final HtmlComplexSearchBudget budget;
  final double fitTolerance;
  final double monotonicityTolerance;
  final HtmlPaginationWorkSlice workSlice;
  final _cache = <_FitCandidateKey, _FitObservation>{};
  final _ledgers = <String, _MonotonicProbeLedger>{};
  int probeCount = 0;
  int cacheHitCount = 0;
  bool budgetExceeded = false;

  bool hasProbeRoom(bool reserveFresh) =>
      probeCount < budget.maxProbeCount - (reserveFresh ? 1 : 0);

  _FitObservation verifyAccepted(String buffer, _FitObservation observation) {
    final cached =
        _cache[_FitCandidateKey(
          html: '$buffer${observation.slice.html}',
          startOffset: observation.slice.startOffset,
          endOffset: observation.slice.endOffset,
        )];
    if (cached == null) {
      throw const HtmlPaginationException(
        code: 'complexFitSearchAcceptedCandidateMissing',
        message: 'The accepted complex HTML candidate was not measured.',
      );
    }
    cacheHitCount += 1;
    cancellationToken.throwIfCancelled();
    return cached;
  }

  Future<_FitObservation?> probe({
    required String bufferedPageHtml,
    required HtmlComplexSlice slice,
    required bool oversizedMinimum,
    required int probeLimit,
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
      return cached;
    }
    if (probeCount >= probeLimit) {
      budgetExceeded = true;
      return null;
    }
    probeCount += 1;
    final measured = await cancellationToken.waitFor(
      measure(
        HtmlPaginationMeasureCandidate(
          html: candidateHtml,
          startOffset: slice.startOffset,
          endOffset: slice.endOffset,
        ),
      ),
    );
    cancellationToken.throwIfCancelled();
    if (!measured.height.isFinite || measured.height < 0) {
      throw const HtmlPaginationException(
        code: 'complexFitSearchInvalidMeasurement',
        message: 'Complex HTML measurement must be finite and non-negative.',
      );
    }
    if (measured.fromCache) cacheHitCount += 1;
    final observation = _FitObservation(
      slice: slice,
      height: measured.height,
      fits: measured.height <= availableHeight + fitTolerance,
      oversizedMinimum: oversizedMinimum,
    );
    _ledgers
        .putIfAbsent(
          bufferedPageHtml,
          () => _MonotonicProbeLedger(tolerance: monotonicityTolerance),
        )
        .record(observation);
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
        throw const HtmlPaginationException(
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
    required this.oversizedMinimum,
  });

  final HtmlComplexSlice slice;
  final double height;
  final bool fits;
  final bool oversizedMinimum;
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
