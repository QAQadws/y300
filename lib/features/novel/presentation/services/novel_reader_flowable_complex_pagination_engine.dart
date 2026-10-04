import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_fit.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_layout_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_fit_searcher.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_work_slice.dart';

abstract interface class NovelReaderFlowableComplexPaginationEngine {
  Future<NovelReaderFlowableComplexPaginationResult> paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPaginationPageContext page,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationMeasureSession measureSession,
    required NovelReaderPaginationCancellationToken cancellationToken,
    NovelReaderFlowableComplexChunkConsumer? onChunk,
  });
}

final class DefaultNovelReaderFlowableComplexPaginationEngine
    implements NovelReaderFlowableComplexPaginationEngine {
  const DefaultNovelReaderFlowableComplexPaginationEngine({
    this.boundaryIndexer = const DefaultNovelReaderComplexHtmlBoundaryIndexer(),
    this.fitSearcher = const DefaultNovelReaderComplexHtmlFitSearcher(),
    this.boundaryCache,
  });

  final NovelReaderComplexHtmlBoundaryIndexer boundaryIndexer;
  final NovelReaderComplexHtmlFitSearcher fitSearcher;
  final NovelReaderComplexHtmlBoundaryCache? boundaryCache;

  @override
  Future<NovelReaderFlowableComplexPaginationResult> paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPaginationPageContext page,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationMeasureSession measureSession,
    required NovelReaderPaginationCancellationToken cancellationToken,
    NovelReaderFlowableComplexChunkConsumer? onChunk,
  }) async {
    _validateAtom(atom);
    cancellationToken.throwIfCancelled();

    late final NovelReaderComplexHtmlSliceSession sliceSession;
    var boundaryIndexBuildCount = 0;
    var boundaryIndexBuildDuration = Duration.zero;
    var boundaryIndexCacheHitCount = 0;
    var boundaryIndexSingleFlightHitCount = 0;

    NovelReaderComplexHtmlSliceSession buildBoundaries() {
      boundaryIndexBuildCount = 1;
      final stopwatch = Stopwatch()..start();
      try {
        return boundaryIndexer.prepare(
          html: atom.atom.html,
          startAnchor: atom.atom.startAnchor,
          sourceAnchorProjection: atom.atom.sourceAnchorProjection,
        );
      } finally {
        stopwatch.stop();
        boundaryIndexBuildDuration += stopwatch.elapsed;
      }
    }

    try {
      final cache = boundaryCache;
      if (cache == null) {
        sliceSession = buildBoundaries();
      } else {
        final cached = await cache.resolve(
          request: NovelReaderComplexHtmlBoundaryCacheRequest(
            episodeId: chapter.episodeId,
            contentHash: chapter.contentHash,
            atomId: atom.atom.atomId,
            html: atom.atom.html,
            startAnchor: atom.atom.startAnchor,
            sourceAnchorProjection: atom.atom.sourceAnchorProjection,
            normalizerRevision: chapter.legacyMarkupNormalization.revision,
          ),
          build: buildBoundaries,
        );
        cancellationToken.throwIfCancelled();
        sliceSession = cached.session;
        boundaryIndexBuildCount = cached.fromCache || cached.joinedInFlight
            ? 0
            : 1;
        boundaryIndexCacheHitCount = cached.fromCache ? 1 : 0;
        boundaryIndexSingleFlightHitCount = cached.joinedInFlight ? 1 : 0;
      }
    } catch (error) {
      if (_isCancellation(error)) {
        rethrow;
      }
      return NovelReaderFlowableComplexPaginationResult(
        chunks: const <NovelReaderFlowableComplexChunk>[],
        boundaryCount: 0,
        probeCount: 0,
        cacheHitCount: 0,
        budgetExceededCount: 0,
        minimumFragmentCount: 0,
        boundaryIndexBuildCount: boundaryIndexBuildCount,
        boundaryIndexBuildDuration: boundaryIndexBuildDuration,
        boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
        boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
        fallbackReason:
            NovelReaderFlowableComplexFallbackReason.boundaryIndexFailure,
      );
    }

    final chunks = <NovelReaderFlowableComplexChunk>[];
    final workSlice = NovelReaderWorkSlice(
      cancellationToken: cancellationToken,
    );
    var startOffset = 0;
    var committedOffset = 0;
    var bufferedPageHtml = page.hasBufferedContent ? page.bufferedHtml : '';
    var probeCount = 0;
    var cacheHitCount = 0;
    var budgetExceededCount = 0;
    var minimumFragmentCount = 0;
    int? preferredWindowGraphemes;

    NovelReaderFlowableComplexPaginationResult snapshot({
      NovelReaderFlowableComplexFallbackReason? fallbackReason,
      int? fallbackMinimumFragmentCount,
      double? measuredMinimumAtomHeight,
      String? measuredMinimumAtomHtml,
      bool includeCollectedChunks = false,
    }) {
      return NovelReaderFlowableComplexPaginationResult(
        chunks: includeCollectedChunks
            ? chunks
            : const <NovelReaderFlowableComplexChunk>[],
        boundaryCount: sliceSession.boundaries.length,
        probeCount: probeCount,
        cacheHitCount: cacheHitCount,
        budgetExceededCount: budgetExceededCount,
        minimumFragmentCount:
            fallbackMinimumFragmentCount ?? minimumFragmentCount,
        boundaryIndexBuildCount: boundaryIndexBuildCount,
        boundaryIndexBuildDuration: boundaryIndexBuildDuration,
        boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
        boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
        committedOffset: committedOffset,
        remainingSlice: fallbackReason == null
            ? null
            : sliceSession.slice(
                startOffset: committedOffset,
                endOffset: sliceSession.textLength,
              ),
        fallbackReason: fallbackReason,
        measuredMinimumAtomHeight: measuredMinimumAtomHeight,
        measuredMinimumAtomHtml: measuredMinimumAtomHtml,
      );
    }

    while (startOffset < sliceSession.textLength) {
      cancellationToken.throwIfCancelled();
      late final NovelReaderComplexHtmlFitResult fit;
      try {
        fit = await fitSearcher.findLargestFittingPrefix(
          session: sliceSession,
          startOffset: startOffset,
          bufferedPageHtml: bufferedPageHtml,
          availableHeight: page.availableHeight,
          preferredWindowGraphemes: preferredWindowGraphemes,
          context: NovelReaderPaginationMeasureContext(
            session: measureSession,
            chapter: chapter,
            key: key,
            atomId: atom.atom.atomId,
          ),
          cancellationToken: cancellationToken,
        );
      } on NovelReaderPaginationException catch (error) {
        if (_mustPropagate(error)) {
          rethrow;
        }
        return snapshot(
          fallbackReason: error.code == 'complexFitSearchNonMonotonic'
              ? NovelReaderFlowableComplexFallbackReason.nonMonotonicMeasurement
              : NovelReaderFlowableComplexFallbackReason.measurementFailure,
        );
      } catch (error) {
        if (_mustPropagate(error)) {
          rethrow;
        }
        return snapshot(
          fallbackReason:
              NovelReaderFlowableComplexFallbackReason.measurementFailure,
        );
      }

      cancellationToken.throwIfCancelled();
      probeCount += fit.probeCount;
      cacheHitCount += fit.cacheHitCount;
      if (fit.budgetExceeded) {
        budgetExceededCount += 1;
      }
      // Count admitted indivisible exceptions as well as minimum overflows.
      if (fit.oversizedMinimumFragment) {
        minimumFragmentCount += 1;
      }
      if (!fit.fits) {
        final isUncommittedFreshMinimum =
            startOffset == committedOffset &&
            fit.slice.endOffset == sliceSession.textLength &&
            (bufferedPageHtml.isEmpty || fit.requiresFreshPage) &&
            !sliceSession.boundaries.any(
              (boundary) =>
                  boundary.textOffset > committedOffset &&
                  boundary.textOffset < sliceSession.textLength &&
                  sliceSession.isLegalBoundary(boundary.textOffset),
            );
        return snapshot(
          fallbackReason:
              NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow,
          fallbackMinimumFragmentCount:
              minimumFragmentCount + (fit.oversizedMinimumFragment ? 0 : 1),
          measuredMinimumAtomHeight: isUncommittedFreshMinimum
              ? fit.measuredHeight
              : null,
          measuredMinimumAtomHtml: isUncommittedFreshMinimum
              ? fit.slice.html
              : null,
        );
      }

      final slice = fit.slice;
      if (slice.endOffset <= startOffset) {
        return snapshot(
          fallbackReason:
              NovelReaderFlowableComplexFallbackReason.invalidSliceProgress,
        );
      }
      final hasRemainder = slice.endOffset < sliceSession.textLength;
      final chunk = NovelReaderFlowableComplexChunk(
        slice: slice,
        composedHeight: fit.measuredHeight,
        requiresFreshPage: fit.requiresFreshPage,
        flushAfterAppend: hasRemainder,
      );
      final consumer = onChunk;
      if (consumer == null) {
        chunks.add(chunk);
      } else {
        // Consumer failures must not become a measurement fallback: it may
        // already have published pages which cannot be rolled back.
        cancellationToken.throwIfCancelled();
        final sealedAndPublished = await cancellationToken.waitFor(
          consumer(chunk, snapshot()),
        );
        cancellationToken.throwIfCancelled();
        if (sealedAndPublished && chunk.flushAfterAppend) {
          committedOffset = slice.endOffset;
        }
      }
      preferredWindowGraphemes = slice.endOffset - startOffset;
      startOffset = slice.endOffset;
      bufferedPageHtml = hasRemainder ? '' : '$bufferedPageHtml${slice.html}';
      await workSlice.yieldIfNeeded();
    }

    cancellationToken.throwIfCancelled();
    return snapshot(includeCollectedChunks: onChunk == null);
  }

  void _validateAtom(NovelReaderClassifiedPaginationAtom atom) {
    final policy = atom.layoutPolicy;
    if (atom.route != NovelReaderPaginationRoute.flowableComplexText &&
            atom.route != NovelReaderPaginationRoute.rubyInline ||
        policy.measure !=
            NovelReaderPaginationMeasurePolicy.htmlRendererRange ||
        policy.split != NovelReaderPaginationSplitPolicy.domBoundaries ||
        policy.placement != NovelReaderPaginationPlacementPolicy.flow) {
      throw ArgumentError.value(
        atom.route,
        'atom',
        'Flowable complex engine requires the DOM-range flow policy.',
      );
    }
  }

  bool _isCancellation(Object error) {
    return error is NovelReaderPaginationException &&
        error.code == 'paginationCancelled';
  }

  bool _mustPropagate(Object error) =>
      _isCancellation(error) ||
      (error is NovelReaderPaginationException &&
          (error.code == 'complexFitSearchCandidateLimitExceeded' ||
              error.code == 'complexFitSearchBudgetUnavailable'));
}
