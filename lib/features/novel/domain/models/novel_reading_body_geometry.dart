import 'dart:math' as math;

/// Geometry of chapter body only, excluding title and chapter transition UI.
final class NovelReadingBodyGeometry {
  const NovelReadingBodyGeometry({
    required this.bodyTop,
    required this.bodyHeight,
    required this.viewportTop,
    required this.effectiveViewportHeight,
    required this.visibleBodyExtent,
    required this.finalBoundaryKnown,
  });

  final double bodyTop;
  final double bodyHeight;
  final double viewportTop;
  final double effectiveViewportHeight;
  final double visibleBodyExtent;
  final bool finalBoundaryKnown;

  bool get isUsable =>
      bodyTop.isFinite &&
      bodyHeight.isFinite &&
      viewportTop.isFinite &&
      effectiveViewportHeight.isFinite &&
      visibleBodyExtent.isFinite &&
      bodyTop >= 0 &&
      bodyHeight >= 0 &&
      effectiveViewportHeight > 0 &&
      visibleBodyExtent >= 0;

  double get bodyRange => math.max(0, bodyHeight - effectiveViewportHeight);

  /// Uses the current sliver layout estimate without forcing distant builds.
  /// Terminal proof is required for completion, not approximate position.
  double? get progressPercent {
    if (!isUsable) return null;
    final range = bodyRange;
    if (range == 0) return 0;
    return ((viewportTop - bodyTop) / range).clamp(0.0, 1.0);
  }

  bool get atBodyEnd =>
      isUsable &&
      finalBoundaryKnown &&
      visibleBodyExtent > 0 &&
      math.max(0, viewportTop - bodyTop) + visibleBodyExtent >=
          bodyHeight - 0.5;

  bool get wholeBodyVisible =>
      atBodyEnd &&
      viewportTop <= bodyTop + 0.5 &&
      visibleBodyExtent >= bodyHeight - 0.5;

  /// Scroll changes do not invalidate a layout or restart a stable-end timer.
  Object get layoutIdentity =>
      (bodyTop, bodyHeight, effectiveViewportHeight, finalBoundaryKnown);

  @override
  bool operator ==(Object other) =>
      other is NovelReadingBodyGeometry &&
      bodyTop == other.bodyTop &&
      bodyHeight == other.bodyHeight &&
      viewportTop == other.viewportTop &&
      effectiveViewportHeight == other.effectiveViewportHeight &&
      visibleBodyExtent == other.visibleBodyExtent &&
      finalBoundaryKnown == other.finalBoundaryKnown;

  @override
  int get hashCode => Object.hash(
    bodyTop,
    bodyHeight,
    viewportTop,
    effectiveViewportHeight,
    visibleBodyExtent,
    finalBoundaryKnown,
  );
}
