import 'dart:math' as math;

import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelReaderProgressSnapshot {
  const NovelReaderProgressSnapshot({
    required this.novelId,
    required this.episodeId,
    required this.flowMode,
    required this.scrollOffset,
    required this.pageIndex,
    this.anchorNodeId,
    required this.progressPercent,
  });

  final String novelId;
  final String episodeId;
  final NovelReaderFlowMode flowMode;
  final double scrollOffset;
  final int pageIndex;
  final String? anchorNodeId;
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
        other.anchorNodeId == anchorNodeId &&
        other.progressPercent == progressPercent;
  }

  @override
  int get hashCode => Object.hash(
    novelId,
    episodeId,
    flowMode,
    scrollOffset,
    pageIndex,
    anchorNodeId,
    progressPercent,
  );

  NovelReaderProgressSnapshot copyWith({
    NovelReaderFlowMode? flowMode,
    double? scrollOffset,
    int? pageIndex,
    String? anchorNodeId,
    bool clearAnchorNodeId = false,
    double? progressPercent,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: flowMode ?? this.flowMode,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      pageIndex: pageIndex ?? this.pageIndex,
      anchorNodeId: clearAnchorNodeId
          ? null
          : (anchorNodeId ?? this.anchorNodeId),
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
      flowMode: flowMode,
      scrollOffset: math.max(0.0, progress.scrollOffset),
      pageIndex: progress.pageIndex < 0 ? 0 : progress.pageIndex,
      anchorNodeId: _normalizeAnchor(progress.anchorNodeId),
      progressPercent: _clampPercent(progress.progressPercent),
    );
  }

  NovelReaderProgressSnapshot verticalSnapshot({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    double maxScrollExtent = 0,
    String? anchorNodeId,
  }) {
    return NovelReaderProgressSnapshot(
      novelId: novelId,
      episodeId: episodeId,
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: math.max(0.0, scrollOffset),
      pageIndex: 0,
      anchorNodeId: _normalizeAnchor(anchorNodeId),
      progressPercent: _percentFromOffset(scrollOffset, maxScrollExtent),
    );
  }

  double restoreScrollOffset(
    NovelReaderProgressSnapshot snapshot, {
    required double maxScrollExtent,
  }) {
    return snapshot.scrollOffset
        .clamp(0.0, math.max(0.0, maxScrollExtent))
        .toDouble();
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
