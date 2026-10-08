import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:y300/features/novel/domain/models/novel_reading_body_geometry.dart';

/// Observes the already laid-out HTML sliver without building distant content.
class NovelReadingBodySliver extends SingleChildRenderObjectWidget {
  const NovelReadingBodySliver({
    super.key,
    required Widget sliver,
    required this.effectiveViewportHeight,
    required this.onGeometry,
    this.layoutIdentity,
  }) : super(child: sliver);

  final double effectiveViewportHeight;
  final ValueChanged<NovelReadingBodyGeometry> onGeometry;
  final Object? layoutIdentity;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNovelReadingBodySliver(
        effectiveViewportHeight: effectiveViewportHeight,
        onGeometry: onGeometry,
        layoutIdentity: layoutIdentity,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxySliver renderObject,
  ) {
    (renderObject as _RenderNovelReadingBodySliver)
      ..effectiveViewportHeight = effectiveViewportHeight
      ..onGeometry = onGeometry
      ..layoutIdentity = layoutIdentity;
  }
}

class _RenderNovelReadingBodySliver extends RenderProxySliver {
  _RenderNovelReadingBodySliver({
    required double effectiveViewportHeight,
    required ValueChanged<NovelReadingBodyGeometry> onGeometry,
    required Object? layoutIdentity,
  }) : _effectiveViewportHeight = effectiveViewportHeight,
       _onGeometry = onGeometry,
       _layoutIdentity = layoutIdentity;

  double _effectiveViewportHeight;
  ValueChanged<NovelReadingBodyGeometry> _onGeometry;
  Object? _layoutIdentity;
  NovelReadingBodyGeometry? _pending;
  NovelReadingBodyGeometry? _lastReported;
  bool _scheduled = false;
  int _callbackGeneration = 0;

  set effectiveViewportHeight(double value) {
    if (_effectiveViewportHeight == value) return;
    _effectiveViewportHeight = value;
    _invalidateCallback();
    markNeedsLayout();
  }

  set onGeometry(ValueChanged<NovelReadingBodyGeometry> value) {
    _onGeometry = value;
  }

  set layoutIdentity(Object? value) {
    if (_layoutIdentity == value) return;
    _layoutIdentity = value;
    _invalidateCallback();
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final currentChild = child;
    final currentGeometry = geometry;
    if (currentChild == null || currentGeometry == null) return;
    // The reader uses a forward, downward vertical viewport. Other growth
    // directions need an explicit coordinate projection rather than a guess.
    final supported =
        constraints.axisDirection == AxisDirection.down &&
        constraints.growthDirection == GrowthDirection.forward;
    final occluded = math.max(
      0.0,
      constraints.viewportMainAxisExtent - _effectiveViewportHeight,
    );
    final visibleExtent = math.max(
      0.0,
      math.min(
        currentGeometry.paintExtent,
        math.min(
          _effectiveViewportHeight,
          constraints.remainingPaintExtent - occluded,
        ),
      ),
    );
    _pending = NovelReadingBodyGeometry(
      bodyTop: constraints.precedingScrollExtent,
      bodyHeight: currentGeometry.scrollExtent,
      viewportTop: constraints.precedingScrollExtent + constraints.scrollOffset,
      effectiveViewportHeight: _effectiveViewportHeight,
      visibleBodyExtent: visibleExtent,
      finalBoundaryKnown: supported && _finalBoundaryLaidOut(currentChild),
    );
    _scheduleCallback();
  }

  void _scheduleCallback() {
    if (_scheduled || _pending == _lastReported) return;
    _scheduled = true;
    final generation = _callbackGeneration;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!attached || generation != _callbackGeneration) return;
      _scheduled = false;
      final current = _pending;
      if (current == null || current == _lastReported) return;
      _lastReported = current;
      _onGeometry(current);
    });
  }

  void _invalidateCallback() {
    _callbackGeneration += 1;
    _scheduled = false;
    _pending = null;
    _lastReported = null;
  }

  @override
  void detach() {
    _invalidateCallback();
    super.detach();
  }
}

bool _finalBoundaryLaidOut(RenderSliver sliver) {
  final geometry = sliver.geometry;
  if (geometry == null || !geometry.scrollExtent.isFinite) return false;
  if (sliver is RenderSliverMultiBoxAdaptor) {
    // Do not ask childCount: with an unbounded builder Flutter may search by
    // constructing distant children. Flutter exposes no public render-tree
    // count; this bounded read does not mutate its protected manager.
    // ignore: invalid_use_of_protected_member
    final count = sliver.childManager.estimatedChildCount;
    if (count == null) return false;
    if (count == 0) return geometry.scrollExtent == 0;
    final last = sliver.lastChild;
    return last != null &&
        last.hasSize &&
        sliver.indexOf(last) == count - 1 &&
        sliver.childScrollOffset(last) != null;
  }
  if (sliver is RenderSliverToBoxAdapter) {
    return sliver.child?.hasSize == true;
  }
  if (sliver is RenderProxySliver) {
    final child = sliver.child;
    return child != null && _finalBoundaryLaidOut(child);
  }
  if (sliver is RenderSliverPadding) {
    final child = sliver.child;
    return child != null && _finalBoundaryLaidOut(child);
  }
  // A grouped sliver is exact only when its member boundaries are laid out.
  // Unknown custom slivers deliberately retain the conservative result.
  if (sliver is RenderSliverMainAxisGroup) {
    var hasChild = false;
    var allKnown = true;
    sliver.visitChildren((child) {
      hasChild = true;
      if (child is! RenderSliver || !_finalBoundaryLaidOut(child)) {
        allKnown = false;
      }
    });
    return hasChild && allKnown;
  }
  return false;
}
