part of 'thread_post_native_flow.dart';

extension on _ThreadPostNativeFlowState {
  bool _preserveImageReflow(_ThreadFlowRun old, _ThreadFlowRun next) {
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final controller = scrollable?.widget.controller;
    final position = scrollable?.position;
    final box = old.boundsKey.currentContext?.findRenderObject();
    if (controller is! ReaderLayoutScrollController ||
        position == null ||
        !position.hasContentDimensions ||
        position.isScrollingNotifier.value ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        ModalRoute.of(context)?.isCurrent == false) {
      next.cancelInlineProbe();
      return true;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || position.axisDirection != AxisDirection.down) {
      next.cancelInlineProbe();
      return true;
    }
    RenderObject? parent = box.parent;
    while (parent is RenderBox) {
      parent = parent.parent;
    }
    if (parent is! RenderSliver) {
      next.cancelInlineProbe();
      return true;
    }
    final reversed =
        parent.constraints.growthDirection == GrowthDirection.reverse;
    final clip = MatrixUtils.transformRect(
      viewport.getTransformTo(box),
      viewport.paintBounds,
    );
    if (!clip.isFinite || clip.width <= 0 || clip.height <= 0) {
      next.cancelInlineProbe();
      return true;
    }

    final before = clip.top.clamp(0.0, old.height);
    if (!next.prefix!.isComplete && (reversed || before == old.height)) {
      // The far boundary determines the placement of a reverse child or of
      // the next visible floor. Wait for its actual extent.
      return false;
    }
    final double? after;
    if (next.preserveInline && before > 0 && before < old.height) {
      final probe = next.inlineProbe ?? _beginInlineProbe(old, next, position);
      if (probe == null ||
          !probe.isAt(position) ||
          probe.before.intersect(clip.inflate(.001)) != probe.before) {
        next.cancelInlineProbe();
        return true;
      }
      if (!probe.done) return false;
      final top = probe.newTop;
      after = top == null ? null : before + top - probe.before.top;
    } else {
      after = _afterBlockReflow(old, next, before);
    }
    if (after == null) {
      next.cancelInlineProbe();
      return true;
    }
    final visibleHeight = clip.bottom.clamp(before, old.height) - before;
    if (!next.prefix!.isComplete && after + visibleHeight > next.height) {
      return false;
    }
    final delta = after - before - (reversed ? next.height - old.height : 0);
    controller.preserveWhileIdle(
      position,
      delta: delta,
      isCurrent: () => _current(next) && identical(_shown, next),
    );
    next.initialSlice = next.inlineProbe?.takeSlice();
    next.cancelInlineProbe();
    return true;
  }
}

double? _afterBlockReflow(
  _ThreadFlowRun old,
  _ThreadFlowRun next,
  double point,
) {
  if (point <= 0) return 0;
  if (point >= old.height) {
    return next.prefix!.isComplete ? next.height : null;
  }
  String? closest;
  var nearestTop = double.negativeInfinity;
  for (final path in next.blockChanges) {
    final bounds = old.blockImages[path];
    if (bounds == null || !next.blockImages.containsKey(path)) return null;
    if (bounds.top <= point && bounds.top > nearestTop) {
      nearestTop = bounds.top;
      closest = path;
    }
  }
  if (closest == null) return point;
  final before = old.blockImages[closest]!;
  final after = next.blockImages[closest]!;
  final local = point - before.top;
  // In an image, preserve the fraction into it. Past the image, unchanged
  // text keeps its distance from that image's measured trailing edge.
  return after.top +
      (local < before.height
          ? after.height * local / before.height
          : after.height + local - before.height);
}
