import 'dart:math' as math;

import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelReaderProgressSnapshot {
  const NovelReaderProgressSnapshot({
    required this.novelId,
    required this.episodeId,
    required this.flowMode,
    required this.scrollOffset,
    required this.pageIndex,
    this.pageCount,
    this.anchorNodeId,
    this.anchorTextOffset = 0,
    this.paginationKey,
    required this.progressPercent,
  });

  final String novelId;
  final String episodeId;
  final NovelReaderFlowMode flowMode;
  final double scrollOffset;
  final int pageIndex;
  final int? pageCount;
  final String? anchorNodeId;
  final int anchorTextOffset;
  final String? paginationKey;
  final double progressPercent;

  bool get isPaged => flowMode != NovelReaderFlowMode.vertical;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelReaderProgressSnapshot &&
        other.novelId == novelId &&
        other.episodeId == episodeId &&
        other.flowMode == flowMode &&
        other.scrollOffset == scrollOffset &&
        other.pageIndex == pageIndex &&
        other.pageCount == pageCount &&
        other.anchorNodeId == anchorNodeId &&
        other.anchorTextOffset == anchorTextOffset &&
        other.paginationKey == paginationKey &&
        other.progressPercent == progressPercent;
  }

  @override
  int get hashCode => Object.hash(
    novelId,
    episodeId,
    flowMode,
    scrollOffset,
    pageIndex,
    pageCount,
    anchorNodeId,
    anchorTextOffset,
    paginationKey,
    progressPercent,
  );

  NovelReaderProgressSnapshot copyWith({
    NovelReaderFlowMode? flowMode,
    double? scrollOffset,
    int? pageIndex,
    int? pageCount,
    bool clearPageCount = false,
    String? anchorNodeId,
    bool clearAnchorNodeId = false,
    int? anchorTextOffset,
    String? paginationKey,
    bool clearPaginationKey = false,
    double? progressPercent,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode ?? this.flowMode,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      pageIndex: pageIndex ?? this.pageIndex,
      pageCount: clearPageCount ? null : (pageCount ?? this.pageCount),
      anchorNodeId: clearAnchorNodeId
          ? null
          : (anchorNodeId ?? this.anchorNodeId),
      anchorTextOffset: anchorTextOffset ?? this.anchorTextOffset,
      paginationKey: clearPaginationKey
          ? null
          : (paginationKey ?? this.paginationKey),
      progressPercent: progressPercent ?? this.progressPercent,
    );
  }
}

class NovelReaderProgressPolicy {
  const NovelReaderProgressPolicy();

  NovelReaderProgressSnapshot initialSnapshot({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode,
      scrollOffset: 0,
      pageIndex: 0,
      progressPercent: 0,
    );
  }

  NovelReaderProgressSnapshot fromReadingProgress({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
    required NovelReadingProgress? progress,
  }) {
    if (progress == null || progress.episodeId != episodeId) {
      return initialSnapshot(
        novelId: novelId,
        episodeId: episodeId,
        flowMode: flowMode,
      );
    }
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: progress.flowMode,
      scrollOffset: math.max(0.0, progress.scrollOffset),
      pageIndex: progress.pageIndex < 0 ? 0 : progress.pageIndex,
      pageCount: _normalizePageCount(progress.pageCount),
      anchorNodeId: _normalizeAnchor(progress.anchorNodeId),
      anchorTextOffset: math.max(0, progress.anchorTextOffset).toInt(),
      paginationKey: _normalizeAnchor(progress.paginationKey),
      progressPercent: _clampPercent(progress.progressPercent),
    );
  }

  NovelReaderProgressSnapshot verticalSnapshot({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    double maxScrollExtent = 0,
    String? anchorNodeId,
    int anchorTextOffset = 0,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: math.max(0.0, scrollOffset),
      pageIndex: 0,
      anchorNodeId: _normalizeAnchor(anchorNodeId),
      anchorTextOffset: math.max(0, anchorTextOffset).toInt(),
      progressPercent: _percentFromOffset(scrollOffset, maxScrollExtent),
    );
  }

  NovelReaderProgressSnapshot pagedSnapshot({
    required String novelId,
    required String episodeId,
    required NovelReaderFlowMode flowMode,
    required int pageIndex,
    required int pageCount,
    required String paginationKey,
    bool isPageCountFinal = true,
    String? anchorNodeId,
    int anchorTextOffset = 0,
  }) {
    if (flowMode == NovelReaderFlowMode.vertical) {
      throw ArgumentError.value(
        flowMode,
        'flowMode',
        'must be a paged flow mode',
      );
    }
    final safePageCount = math.max(1, pageCount);
    final safePageIndex = pageIndex.clamp(0, safePageCount - 1).toInt();
    final normalizedKey = _normalizeAnchor(paginationKey);
    if (normalizedKey == null) {
      throw ArgumentError.value(
        paginationKey,
        'paginationKey',
        'must not be empty',
      );
    }
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode,
      scrollOffset: 0,
      pageIndex: safePageIndex,
      pageCount: isPageCountFinal ? safePageCount : null,
      anchorNodeId: _normalizeAnchor(anchorNodeId),
      anchorTextOffset: math.max(0, anchorTextOffset).toInt(),
      paginationKey: normalizedKey,
      progressPercent: !isPageCountFinal ? 0 : safePageIndex / safePageCount,
    );
  }

  double restoreScrollOffset(
    NovelReaderProgressSnapshot snapshot, {
    required double maxScrollExtent,
    double viewportDimension = 0,
  }) {
    final safeMax = math.max(0.0, maxScrollExtent);
    // Offset and page numbers belong to a previous layout. Percentage is the
    // stable cross-layout position, so prefer it whenever it is meaningful.
    if (snapshot.progressPercent.isFinite && snapshot.progressPercent > 0) {
      final target = _clampPercent(snapshot.progressPercent) * safeMax;
      if (snapshot.flowMode == NovelReaderFlowMode.vertical ||
          snapshot.pageCount != null) {
        return target;
      }
      return math.max(0.0, target - math.max(0.0, viewportDimension));
    }
    return snapshot.scrollOffset.clamp(0.0, safeMax).toDouble();
  }

  int? _normalizePageCount(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  double _percentFromOffset(double offset, double maxScrollExtent) {
    if (maxScrollExtent <= 0) {
      return 0;
    }
    return _clampPercent(offset / maxScrollExtent);
  }

  double _clampPercent(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  String? _normalizeAnchor(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
