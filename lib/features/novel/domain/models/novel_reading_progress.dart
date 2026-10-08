import 'novel_reader_anchor_format.dart';
import 'novel_reader_preferences.dart';

/// Percentage provenance is independent of the semantic anchor format.
/// Unknown values are retained so a newer client can still interpret them.
abstract final class NovelProgressPercentBasis {
  static const legacyReaderLayout = 'legacyReaderLayout';
  static const bodyGeometryV1 = 'bodyGeometryV1';
  static const pagedStartV1 = 'pagedStartV1';
}

class NovelReadingProgress {
  const NovelReadingProgress({
    required this.novelId,
    required this.episodeId,
    required this.scrollOffset,
    required this.updatedAt,
    this.flowMode = NovelReaderFlowMode.vertical,
    this.pageIndex = 0,
    this.pageCount,
    this.anchorNodeId,
    this.anchorTextOffset = 0,
    this.paginationKey,
    this.progressPercent = 0,
    this.anchorFormatVersion = NovelReaderAnchorFormat.legacyUnknown,
    this.anchorTextIdentity,
    this.isProgressPercentValid,
    this.percentBasis = NovelProgressPercentBasis.legacyReaderLayout,
  });

  final String novelId;
  final String episodeId;
  final double scrollOffset;
  final DateTime updatedAt;
  final NovelReaderFlowMode flowMode;
  final int pageIndex;
  final int? pageCount;
  final String? anchorNodeId;
  final int anchorTextOffset;
  final String? paginationKey;
  final double progressPercent;
  final int anchorFormatVersion;
  final String? anchorTextIdentity;
  final bool? isProgressPercentValid;
  final String percentBasis;
}
