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
    this.boundaryIndexCacheHitCount = 0,
    this.boundaryIndexSingleFlightHitCount = 0,
    this.fallbackReason,
  }) : chunks = List<NovelReaderFlowableComplexChunk>.unmodifiable(chunks),
       assert(boundaryCount >= 0),
       assert(probeCount >= 0),
       assert(cacheHitCount >= 0),
       assert(budgetExceededCount >= 0),
       assert(minimumFragmentCount >= 0),
       assert(boundaryIndexBuildCount >= 0),
       assert(boundaryIndexCacheHitCount >= 0),
       assert(boundaryIndexSingleFlightHitCount >= 0),
       assert(fallbackReason == null || chunks.isEmpty);

  final List<NovelReaderFlowableComplexChunk> chunks;
  final int boundaryCount;
  final int probeCount;
  final int cacheHitCount;
  final int budgetExceededCount;
  final int minimumFragmentCount;
  final int boundaryIndexBuildCount;
  final int boundaryIndexCacheHitCount;
  final int boundaryIndexSingleFlightHitCount;
  final NovelReaderFlowableComplexFallbackReason? fallbackReason;

  bool get requiresAtomicFallback => fallbackReason != null;
}
