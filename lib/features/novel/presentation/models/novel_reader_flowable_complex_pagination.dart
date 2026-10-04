import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';

enum NovelReaderFlowableComplexFallbackReason {
  boundaryIndexFailure,
  nonMonotonicMeasurement,
  measurementFailure,
  minimumFragmentOverflow,
  invalidSliceProgress,
}

@immutable
final class NovelReaderPaginationPageContext {
  const NovelReaderPaginationPageContext({
    required this.bufferedHtml,
    required this.hasBufferedContent,
    required this.availableHeight,
  }) : assert(availableHeight > 0);

  final String bufferedHtml;
  final bool hasBufferedContent;
  final double availableHeight;
}

@immutable
final class NovelReaderFlowableComplexChunk {
  const NovelReaderFlowableComplexChunk({
    required this.slice,
    required this.composedHeight,
    required this.requiresFreshPage,
    required this.flushAfterAppend,
  }) : assert(composedHeight >= 0);

  final NovelReaderComplexHtmlSlice slice;

  /// Renderer height of the complete page buffer after appending [slice].
  final double composedHeight;
  final bool requiresFreshPage;
  final bool flushAfterAppend;
}

/// Consumes one measured chunk before the engine probes the next range.
///
/// Return true only after this chunk has sealed a page and its publication has
/// completed. An open final chunk does not establish a committed boundary.
typedef NovelReaderFlowableComplexChunkConsumer =
    Future<bool> Function(
      NovelReaderFlowableComplexChunk chunk,
      NovelReaderFlowableComplexPaginationResult progress,
    );

@immutable
final class NovelReaderFlowableComplexPaginationResult {
  NovelReaderFlowableComplexPaginationResult({
    required List<NovelReaderFlowableComplexChunk> chunks,
    required this.boundaryCount,
    required this.probeCount,
    required this.cacheHitCount,
    required this.budgetExceededCount,
    required this.minimumFragmentCount,
    this.boundaryIndexBuildCount = 0,
    this.boundaryIndexBuildDuration = Duration.zero,
    this.boundaryIndexCacheHitCount = 0,
    this.boundaryIndexSingleFlightHitCount = 0,
    this.committedOffset = 0,
    this.remainingSlice,
    this.fallbackReason,
    this.measuredMinimumAtomHeight,
    this.measuredMinimumAtomHtml,
  }) : chunks = List<NovelReaderFlowableComplexChunk>.unmodifiable(chunks),
       assert(boundaryCount >= 0),
       assert(probeCount >= 0),
       assert(cacheHitCount >= 0),
       assert(budgetExceededCount >= 0),
       assert(minimumFragmentCount >= 0),
       assert(boundaryIndexBuildCount >= 0),
       assert(boundaryIndexCacheHitCount >= 0),
       assert(boundaryIndexSingleFlightHitCount >= 0),
       assert(committedOffset >= 0),
       assert(
         remainingSlice == null ||
             (fallbackReason != null &&
                 remainingSlice.startOffset == committedOffset),
       ),
       assert(fallbackReason == null || chunks.isEmpty),
       assert(
         measuredMinimumAtomHeight == null ||
             (measuredMinimumAtomHeight.isFinite &&
                 measuredMinimumAtomHeight >= 0 &&
                 fallbackReason ==
                     NovelReaderFlowableComplexFallbackReason
                         .minimumFragmentOverflow),
       ),
       assert(
         (measuredMinimumAtomHeight == null) ==
             (measuredMinimumAtomHtml == null),
       );

  final List<NovelReaderFlowableComplexChunk> chunks;
  final int boundaryCount;
  final int probeCount;
  final int cacheHitCount;
  final int budgetExceededCount;
  final int minimumFragmentCount;
  final int boundaryIndexBuildCount;
  final Duration boundaryIndexBuildDuration;
  final int boundaryIndexCacheHitCount;
  final int boundaryIndexSingleFlightHitCount;

  /// DOM grapheme boundary acknowledged as sealed and published by the host.
  /// A collecting call without a consumer has no publication acknowledgement.
  final int committedOffset;

  /// Complete uncommitted tail after a recoverable measurement failure.
  /// Null means the boundary session could not be prepared, or no fallback ran.
  final NovelReaderComplexHtmlSlice? remainingSlice;
  final NovelReaderFlowableComplexFallbackReason? fallbackReason;

  /// The complete uncommitted tail was the only legal minimum and was measured
  /// on a fresh page. The host can preserve that indivisible block without
  /// measuring it again; this is not evidence for an arbitrary atom fallback.
  final double? measuredMinimumAtomHeight;

  /// Exact serialized candidate corresponding to [measuredMinimumAtomHeight].
  /// Reusing its height does not assume the original atom serializes identically.
  final String? measuredMinimumAtomHtml;

  bool get requiresAtomicFallback => fallbackReason != null;
}
