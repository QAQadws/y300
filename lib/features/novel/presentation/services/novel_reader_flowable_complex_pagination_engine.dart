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

abstract interface class NovelReaderFlowableComplexPaginationEngine {
  Future<NovelReaderFlowableComplexPaginationResult> paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderPaginationPageContext page,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required NovelReaderPaginationMeasureSession measureSession,
    required NovelReaderPaginationCancellationToken cancellationToken,
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
  }) async {
    _validateAtom(atom);
    cancellationToken.throwIfCancelled();

    late final NovelReaderComplexHtmlSliceSession sliceSession;
    var boundaryIndexBuildCount = 0;
    var boundaryIndexCacheHitCount = 0;
    var boundaryIndexSingleFlightHitCount = 0;
    try {
      final cache = boundaryCache;
      if (cache == null) {
        boundaryIndexBuildCount = 1;
        sliceSession = boundaryIndexer.prepare(
          html: atom.atom.html,
          startAnchor: atom.atom.startAnchor,
        );
      } else {
        final cached = await cache.resolve(
          request: NovelReaderComplexHtmlBoundaryCacheRequest(
            episodeId: chapter.episodeId,
            contentHash: chapter.contentHash,
            atomId: atom.atom.atomId,
            html: atom.atom.html,
            startAnchor: atom.atom.startAnchor,
            normalizerRevision: chapter.legacyMarkupNormalization.revision,
          ),
          build: () {
            boundaryIndexBuildCount = 1;
            return boundaryIndexer.prepare(
              html: atom.atom.html,
              startAnchor: atom.atom.startAnchor,
            );
          },
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
      return _fallback(
        NovelReaderFlowableComplexFallbackReason.boundaryIndexFailure,
        boundaryIndexBuildCount: boundaryIndexBuildCount,
        boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
        boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
      );
    }

    final chunks = <NovelReaderFlowableComplexChunk>[];
    var startOffset = 0;
    var bufferedPageHtml = page.hasBufferedContent ? page.bufferedHtml : '';
    var probeCount = 0;
    var cacheHitCount = 0;
    var budgetExceededCount = 0;

    while (startOffset < sliceSession.textLength) {
      cancellationToken.throwIfCancelled();
      late final NovelReaderComplexHtmlFitResult fit;
      try {
        fit = await fitSearcher.findLargestFittingPrefix(
          session: sliceSession,
          startOffset: startOffset,
          bufferedPageHtml: bufferedPageHtml,
          availableHeight: page.availableHeight,
          context: NovelReaderPaginationMeasureContext(
            session: measureSession,
            chapter: chapter,
            key: key,
            atomId: atom.atom.atomId,
          ),
          cancellationToken: cancellationToken,
        );
      } on NovelReaderPaginationException catch (error) {
        if (_isCancellation(error)) {
          rethrow;
        }
        return _fallback(
          error.code == 'complexFitSearchNonMonotonic'
              ? NovelReaderFlowableComplexFallbackReason.nonMonotonicMeasurement
              : NovelReaderFlowableComplexFallbackReason.measurementFailure,
          boundaryCount: sliceSession.boundaries.length,
          probeCount: probeCount,
          cacheHitCount: cacheHitCount,
          budgetExceededCount: budgetExceededCount,
          boundaryIndexBuildCount: boundaryIndexBuildCount,
          boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
          boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
        );
      } catch (error) {
        if (_isCancellation(error)) {
          rethrow;
        }
        return _fallback(
          NovelReaderFlowableComplexFallbackReason.measurementFailure,
          boundaryCount: sliceSession.boundaries.length,
          probeCount: probeCount,
          cacheHitCount: cacheHitCount,
          budgetExceededCount: budgetExceededCount,
          boundaryIndexBuildCount: boundaryIndexBuildCount,
          boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
          boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
        );
      }

      probeCount += fit.probeCount;
      cacheHitCount += fit.cacheHitCount;
      if (fit.budgetExceeded) {
        budgetExceededCount += 1;
      }
      if (!fit.fits) {
        return _fallback(
          NovelReaderFlowableComplexFallbackReason.minimumFragmentOverflow,
          boundaryCount: sliceSession.boundaries.length,
          probeCount: probeCount,
          cacheHitCount: cacheHitCount,
          budgetExceededCount: budgetExceededCount,
          minimumFragmentCount: 1,
          boundaryIndexBuildCount: boundaryIndexBuildCount,
          boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
          boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
        );
      }

      final slice = fit.slice;
      if (slice.endOffset <= startOffset) {
        return _fallback(
          NovelReaderFlowableComplexFallbackReason.invalidSliceProgress,
          boundaryCount: sliceSession.boundaries.length,
          probeCount: probeCount,
          cacheHitCount: cacheHitCount,
          budgetExceededCount: budgetExceededCount,
          boundaryIndexBuildCount: boundaryIndexBuildCount,
          boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
          boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
        );
      }
      final hasRemainder = slice.endOffset < sliceSession.textLength;
      chunks.add(
        NovelReaderFlowableComplexChunk(
          slice: slice,
          composedHeight: fit.measuredHeight,
          requiresFreshPage: fit.requiresFreshPage,
          flushAfterAppend: hasRemainder,
        ),
      );
      startOffset = slice.endOffset;
      bufferedPageHtml = hasRemainder ? '' : '$bufferedPageHtml${slice.html}';
    }

    cancellationToken.throwIfCancelled();
    return NovelReaderFlowableComplexPaginationResult(
      chunks: chunks,
      boundaryCount: sliceSession.boundaries.length,
      probeCount: probeCount,
      cacheHitCount: cacheHitCount,
      budgetExceededCount: budgetExceededCount,
      minimumFragmentCount: 0,
      boundaryIndexBuildCount: boundaryIndexBuildCount,
      boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
      boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
    );
  }

  NovelReaderFlowableComplexPaginationResult _fallback(
    NovelReaderFlowableComplexFallbackReason reason, {
    int boundaryCount = 0,
    int probeCount = 0,
    int cacheHitCount = 0,
    int budgetExceededCount = 0,
    int minimumFragmentCount = 0,
    int boundaryIndexBuildCount = 0,
    int boundaryIndexCacheHitCount = 0,
    int boundaryIndexSingleFlightHitCount = 0,
  }) {
    return NovelReaderFlowableComplexPaginationResult(
      chunks: const <NovelReaderFlowableComplexChunk>[],
      boundaryCount: boundaryCount,
      probeCount: probeCount,
      cacheHitCount: cacheHitCount,
      budgetExceededCount: budgetExceededCount,
      minimumFragmentCount: minimumFragmentCount,
      boundaryIndexBuildCount: boundaryIndexBuildCount,
      boundaryIndexCacheHitCount: boundaryIndexCacheHitCount,
      boundaryIndexSingleFlightHitCount: boundaryIndexSingleFlightHitCount,
      fallbackReason: reason,
    );
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
}
