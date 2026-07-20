import 'package:flutter/foundation.dart';

@immutable
class NovelReaderPaginationDiagnostics {
  const NovelReaderPaginationDiagnostics({
    required this.episodeId,
    required this.paginationKey,
    required this.pageCount,
    required this.layoutDuration,
    required this.reflowCount,
    required this.unknownImageDimensionCount,
    required this.overflowPageCount,
    required this.cacheHit,
    required this.flowUnitCount,
  });

  final String episodeId;
  final String paginationKey;
  final int pageCount;
  final Duration layoutDuration;
  final int reflowCount;
  final int unknownImageDimensionCount;
  final int overflowPageCount;
  final bool cacheHit;
  final int flowUnitCount;

  @override
  String toString() {
    return 'NovelReaderPaginationDiagnostics('
        'episode=$episodeId, pages=$pageCount, '
        'durationMs=${layoutDuration.inMilliseconds}, '
        'reflows=$reflowCount, unknownImageDimensions='
        '$unknownImageDimensionCount, overflowPages=$overflowPageCount, '
        'cacheHit=$cacheHit, flowUnits=$flowUnitCount)';
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
