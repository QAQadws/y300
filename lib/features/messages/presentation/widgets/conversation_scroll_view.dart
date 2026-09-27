import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps a centered conversation's short content at the top of its viewport.
class ConversationScrollView extends CustomScrollView {
  const ConversationScrollView({
    super.key,
    required super.controller,
    required super.center,
    required super.slivers,
  }) : super(
         reverse: true,
         keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
       );

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset offset,
    AxisDirection axisDirection,
    List<Widget> slivers,
  ) => _ConversationViewport(
    axisDirection: axisDirection,
    offset: offset,
    center: center,
    slivers: slivers,
  );
}

class _ConversationViewport extends Viewport {
  _ConversationViewport({
    required super.axisDirection,
    required super.offset,
    required super.center,
    required super.slivers,
  }) : super(scrollCacheExtent: const ScrollCacheExtent.viewport(1));

  @override
  RenderViewport createRenderObject(BuildContext context) =>
      _RenderConversationViewport(
        axisDirection: axisDirection,
        crossAxisDirection: Viewport.getDefaultCrossAxisDirection(
          context,
          axisDirection,
        ),
        offset: offset,
      );

  @override
  void updateRenderObject(BuildContext context, RenderViewport renderObject) {
    renderObject
      ..axisDirection = axisDirection
      ..crossAxisDirection = Viewport.getDefaultCrossAxisDirection(
        context,
        axisDirection,
      )
      ..offset = offset;
    // The render object owns the measured anchor; widget rebuilds must not
    // reset it before the next layout.
  }
}

class _RenderConversationViewport extends RenderViewport {
  _RenderConversationViewport({
    required super.axisDirection,
    required super.crossAxisDirection,
    required super.offset,
  }) : super(scrollCacheExtent: const ScrollCacheExtent.viewport(1));

  static const _extentTolerance = 0.0001;
  static const _maxAnchorAdjustments = 3;
  double _layoutAnchor = 0;

  @override
  double get anchor => _layoutAnchor;

  @override
  set anchor(double value) {
    assert(value >= 0 && value <= 1);
    if (_layoutAnchor == value) return;
    _layoutAnchor = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final extent = size.height;
    if (!extent.isFinite || extent <= 0) {
      _layoutAnchor = 0;
      super.performLayout();
      return;
    }

    // One viewport of cache on each side reaches the end of both lists when
    // they fit on screen, including the newer list initially below the center.
    // Thus short-content alignment uses laid-out heights, not lazy estimates.
    for (var attempt = 0; attempt < _maxAnchorAdjustments; attempt++) {
      super.performLayout();
      final nextAnchor = _topAlignedAnchor(extent);
      if ((anchor - nextAnchor).abs() * extent <= _extentTolerance) return;
      // This is a result of the active layout, not a new external mutation.
      // The public setter would mark this viewport dirty during its own layout.
      _layoutAnchor = nextAnchor;
    }
    // Keep any final correction within this frame without an unbounded loop.
    super.performLayout();
  }

  double _topAlignedAnchor(double viewportExtent) {
    var historyExtent = 0.0;
    var newerExtent = 0.0;
    var reachedCenter = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child == center) reachedCenter = true;
      final childExtent = child.geometry?.scrollExtent;
      if (childExtent == null || !childExtent.isFinite) return 0;
      if (reachedCenter) {
        historyExtent += childExtent;
      } else {
        newerExtent += childExtent;
      }
    }
    if (!reachedCenter ||
        historyExtent + newerExtent > viewportExtent + _extentTolerance) {
      return 0;
    }
    // With reverse scrolling, the center is measured from the bottom. Put it
    // exactly below history so that history and newer messages start at y=0.
    return (1 - historyExtent / viewportExtent).clamp(0.0, 1.0);
  }
}
