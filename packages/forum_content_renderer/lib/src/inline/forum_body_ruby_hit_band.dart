import 'forum_body_ruby_group_metrics.dart';

/// Shared native-band hit policy for text columns and composite child trees.
/// Numeric bands choose a child; only its live source projection proves a hit.
({int annotationIndex, bool forced}) resolveForumBodyRubyHitBand({
  required ForumBodyRubyGroupMetrics metrics,
  required double y,
  required bool baseHasText,
  required bool Function(int rank) annotationHasText,
}) {
  double distance(double top, double bottom) => y < top
      ? top - y
      : y > bottom
      ? y - bottom
      : 0;
  var selected = -1;
  var bestTop = metrics.baseBandTop;
  var bestDistance = distance(metrics.baseBandTop, metrics.baseBandBottom);
  var nearest = -1;
  var nearestDistance = double.infinity;
  var nearestTop = double.negativeInfinity;
  for (final (index, band) in metrics.annotations.indexed) {
    if (!annotationHasText(index)) continue;
    final delta = distance(band.bandTop, band.bandBottom);
    // Keep the existing exact-midpoint convention: the physically lower band.
    if (delta < nearestDistance ||
        (delta == nearestDistance && band.bandTop > nearestTop)) {
      nearestDistance = delta;
      nearestTop = band.bandTop;
      nearest = index;
    }
    if (delta < bestDistance ||
        (delta == bestDistance && band.bandTop > bestTop)) {
      bestDistance = delta;
      bestTop = band.bandTop;
      selected = index;
    }
  }
  final forced = selected < 0 && !baseHasText;
  if (forced) selected = nearest;
  return (annotationIndex: selected, forced: forced);
}
