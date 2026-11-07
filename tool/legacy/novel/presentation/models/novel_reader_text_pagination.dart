import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

final class NovelReaderTextLineRange {
  const NovelReaderTextLineRange({
    required this.layoutStart,
    required this.layoutEnd,
    required this.sourceStart,
    required this.sourceEnd,
    required this.top,
    required this.bottom,
    required this.hardBreak,
    required this.hasRenderableContent,
  });

  final int layoutStart;
  final int layoutEnd;
  final int sourceStart;
  final int sourceEnd;
  final double top;
  final double bottom;
  final bool hardBreak;
  final bool hasRenderableContent;

  double get height => bottom - top;
}

final class NovelReaderTextLayoutMetrics {
  NovelReaderTextLayoutMetrics({
    required this.runId,
    required List<NovelReaderTextLineRange> lineRanges,
    required this.totalHeight,
    required this.width,
    required this.typographySignature,
  }) : lineRanges = List<NovelReaderTextLineRange>.unmodifiable(lineRanges);

  final String runId;
  final List<NovelReaderTextLineRange> lineRanges;
  final double totalHeight;
  final double width;
  final String typographySignature;
}

final class NovelReaderTextPageChunk {
  const NovelReaderTextPageChunk({
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.sourceStart,
    required this.sourceEnd,
    required this.usedHeight,
    required this.isOversized,
    required this.hasRenderableContent,
    this.structuralBreakCount = 0,
  });

  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final int sourceStart;
  final int sourceEnd;
  final double usedHeight;
  final bool isOversized;
  final bool hasRenderableContent;

  /// Number of standalone `<br>` elements represented by this chunk.
  ///
  /// A standalone break is layout structure rather than independently
  /// renderable content. The page composer uses this count to distinguish one
  /// separator between two text runs from additional blank lines.
  final int structuralBreakCount;

  bool get isStructuralBreak => structuralBreakCount > 0;
}

final class NovelReaderTextPaginationResult {
  NovelReaderTextPaginationResult({
    required List<NovelReaderTextPageChunk> chunks,
    required this.metrics,
    required this.metricsCacheHit,
    required this.layoutCount,
  }) : chunks = List<NovelReaderTextPageChunk>.unmodifiable(chunks);

  final List<NovelReaderTextPageChunk> chunks;
  final NovelReaderTextLayoutMetrics metrics;
  final bool metricsCacheHit;
  final int layoutCount;
}
