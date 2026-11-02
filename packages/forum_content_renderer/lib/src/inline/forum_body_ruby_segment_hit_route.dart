import 'package:flutter/painting.dart';

import 'forum_body_ruby_group_metrics.dart';

typedef ForumBodyRubySegmentHitRoute = ({
  int columnIndex,
  int? gapIndex,
  int? spanIndex,
  int? annotationGapIndex,
  bool forced,
});

/// Physical member routing over the one measured segment. Source positions
/// still come from the actual current child; numeric geometry grants no source
/// or paint ownership. Rank indexes are prepared by the existing transaction.
ForumBodyRubySegmentHitRoute resolveForumBodyRubySegmentHitRoute({
  required ForumBodyRubySegmentMetrics metrics,
  required Offset point,
  required Map<int, List<int>> spanRanks,
  required Map<int, List<int>> annotationGapRanks,
  required bool Function(int column) baseHasText,
}) {
  if (!point.dx.isFinite || !point.dy.isFinite) {
    throw ArgumentError.value(point);
  }
  double distance(double coordinate, double start, double end) =>
      coordinate < start
      ? start - coordinate
      : coordinate > end
      ? coordinate - end
      : 0;
  var column = 0;
  int? gap;
  var horizontal = double.infinity;
  var left = double.negativeInfinity;
  for (var i = 0; i < metrics.columns.length; i++) {
    final start = metrics.columnLefts[i];
    final delta = distance(point.dx, start, start + metrics.columnWidths[i]);
    if (delta < horizontal || (delta == horizontal && start > left)) {
      column = i;
      horizontal = delta;
      left = start;
    }
  }
  for (var i = 0; i < metrics.gaps.length; i++) {
    final item = metrics.gaps[i];
    final delta = distance(point.dx, item.left, item.left + item.width);
    if (delta < horizontal || (delta == horizontal && item.left > left)) {
      gap = i;
      horizontal = delta;
      left = item.left;
    }
  }
  int? edge = gap == null ? null : metrics.gaps[gap].input.beforeColumn;
  for (
    var i = 1;
    metrics.annotationGaps.isNotEmpty && i < metrics.columns.length;
    i++
  ) {
    final start = metrics.direction == TextDirection.ltr
        ? metrics.columnLefts[i - 1] + metrics.columnWidths[i - 1]
        : metrics.columnLefts[i] + metrics.columnWidths[i];
    final end = metrics.direction == TextDirection.ltr
        ? metrics.columnLefts[i]
        : metrics.columnLefts[i - 1];
    if (point.dx > start && point.dx < end) {
      edge = i;
      break;
    }
  }
  int? spanFor(int rank) {
    if (edge == null) return _spanFor(metrics, spanRanks, column, rank);
    for (final i in spanRanks[rank] ?? const <int>[]) {
      final span = metrics.spans[i];
      if (span.input.startColumn >= edge) break;
      if (span.input.endColumn > edge && span.metrics.hasAnnotation) {
        return i;
      }
    }
    return null;
  }

  int? annotationGapFor(int rank) {
    if (edge == null) return null;
    int? found;
    var bestDistance = double.infinity;
    var bestLeft = double.negativeInfinity;
    for (final i in annotationGapRanks[rank] ?? const <int>[]) {
      final item = metrics.annotationGaps[i];
      if (item.input.beforeColumn != edge) continue;
      final delta = distance(point.dx, item.left, item.left + item.width);
      if (delta < bestDistance ||
          (delta == bestDistance && item.left > bestLeft)) {
        found = i;
        bestDistance = delta;
        bestLeft = item.left;
      }
    }
    return found;
  }

  final own = gap == null ? metrics.columns[column] : metrics.gaps[gap].font;
  var selected = -1;
  var bestTop = own.baseBandTop;
  var best = distance(point.dy, own.baseBandTop, own.baseBandBottom);
  var nearest = -1;
  var nearestDistance = double.infinity;
  var nearestTop = double.negativeInfinity;
  for (var rank = 0; rank < own.annotations.length; rank++) {
    if (!(edge == null && own.annotations[rank].hasAnnotation) &&
        spanFor(rank) == null &&
        annotationGapFor(rank) == null) {
      continue;
    }
    final band = own.annotations[rank];
    final delta = distance(point.dy, band.bandTop, band.bandBottom);
    if (delta < nearestDistance ||
        (delta == nearestDistance && band.bandTop > nearestTop)) {
      nearest = rank;
      nearestDistance = delta;
      nearestTop = band.bandTop;
    }
    if (delta < best || (delta == best && band.bandTop > bestTop)) {
      selected = rank;
      best = delta;
      bestTop = band.bandTop;
    }
  }
  final forced = selected < 0 && gap == null && !baseHasText(column);
  if (forced) selected = nearest;

  return (
    columnIndex: column,
    gapIndex: gap,
    spanIndex: selected < 0 ? null : spanFor(selected),
    annotationGapIndex: selected < 0 ? null : annotationGapFor(selected),
    forced: forced,
  );
}

int? _spanFor(
  ForumBodyRubySegmentMetrics metrics,
  Map<int, List<int>> ranks,
  int column,
  int rank,
) {
  for (final index in ranks[rank] ?? const <int>[]) {
    final span = metrics.spans[index];
    if (span.input.startColumn > column) break;
    if (column < span.input.endColumn && span.metrics.hasAnnotation) {
      return index;
    }
  }
  return null;
}
