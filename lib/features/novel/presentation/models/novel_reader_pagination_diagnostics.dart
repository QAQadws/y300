import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';

@immutable
class NovelReaderPaginationDiagnostics {
  NovelReaderPaginationDiagnostics({
    required this.episodeId,
    required this.paginationKey,
    required this.pageCount,
    required this.layoutDuration,
    required this.reflowCount,
    required this.unknownImageDimensionCount,
    required this.overflowPageCount,
    required this.cacheHit,
    required this.flowUnitCount,
    this.atomCount = 0,
    this.measurementCount = 0,
    this.measurementCacheHitCount = 0,
    this.measurementDuration = Duration.zero,
    this.availableHeight = 0,
    this.averageTextPageFullness = 0,
    this.lowFullnessPageCount = 0,
    Map<NovelReaderPageGapReason, int> gapReasonCounts =
        const <NovelReaderPageGapReason, int>{},
    Map<NovelReaderPaginationAtomKind, int> atomKindCounts =
        const <NovelReaderPaginationAtomKind, int>{},
    List<NovelReaderPaginationMeasurementSample> measurementSamples =
        const <NovelReaderPaginationMeasurementSample>[],
  }) : gapReasonCounts = Map<NovelReaderPageGapReason, int>.unmodifiable(
         gapReasonCounts,
       ),
       atomKindCounts = Map<NovelReaderPaginationAtomKind, int>.unmodifiable(
         atomKindCounts,
       ),
       measurementSamples =
           List<NovelReaderPaginationMeasurementSample>.unmodifiable(
             measurementSamples,
           );

  final String episodeId;
  final String paginationKey;
  final int pageCount;
  final Duration layoutDuration;
  final int reflowCount;
  final int unknownImageDimensionCount;
  final int overflowPageCount;
  final bool cacheHit;
  final int flowUnitCount;
  final int atomCount;
  final int measurementCount;
  final int measurementCacheHitCount;
  final Duration measurementDuration;
  final double availableHeight;
  final double averageTextPageFullness;
  final int lowFullnessPageCount;
  final Map<NovelReaderPageGapReason, int> gapReasonCounts;
  final Map<NovelReaderPaginationAtomKind, int> atomKindCounts;
  final List<NovelReaderPaginationMeasurementSample> measurementSamples;

  @override
  String toString() {
    return 'NovelReaderPaginationDiagnostics('
        'episode=$episodeId, pages=$pageCount, '
        'durationMs=${layoutDuration.inMilliseconds}, '
        'reflows=$reflowCount, unknownImageDimensions='
        '$unknownImageDimensionCount, overflowPages=$overflowPageCount, '
        'cacheHit=$cacheHit, flowUnits=$flowUnitCount, atoms=$atomCount, '
        'measurements=$measurementCount, measurementCacheHits='
        '$measurementCacheHitCount, measurementMs='
        '${measurementDuration.inMilliseconds}, averageTextFullness='
        '${averageTextPageFullness.toStringAsFixed(2)}, '
        'lowFullnessPages=$lowFullnessPageCount, gapReasons='
        '$gapReasonCounts, atomKinds=$atomKindCounts)';
  }
}

abstract interface class NovelReaderPaginationDiagnosticsSink {
  void record(NovelReaderPaginationDiagnostics diagnostics);
}

final class NovelReaderNoopPaginationDiagnosticsSink
    implements NovelReaderPaginationDiagnosticsSink {
  const NovelReaderNoopPaginationDiagnosticsSink();

  @override
  void record(NovelReaderPaginationDiagnostics diagnostics) {}
}

/// Keeps Phase 5 diagnostics available during development without emitting
/// production logs or body contents.
final class NovelReaderDebugPaginationDiagnosticsSink
    implements NovelReaderPaginationDiagnosticsSink {
  const NovelReaderDebugPaginationDiagnosticsSink();

  @override
  void record(NovelReaderPaginationDiagnostics diagnostics) {
    if (kDebugMode) {
      debugPrint('[NovelPagination] $diagnostics');
    }
  }
}
