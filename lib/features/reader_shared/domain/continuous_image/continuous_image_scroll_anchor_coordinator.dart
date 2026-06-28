import 'continuous_image_extent_registry.dart';
import 'continuous_image_layout_resolver.dart';
import 'continuous_image_models.dart';

enum ContinuousImageScrollCompensationTiming { none, immediate, deferred }

class ContinuousImageScrollAnchorMetrics {
  const ContinuousImageScrollAnchorMetrics({
    required this.scrollOffset,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportExtent,
    required this.userScrollDirection,
    this.isScrollActivityInProgress = false,
  }) : assert(viewportExtent >= 0);

  final double scrollOffset;
  final double minScrollExtent;
  final double maxScrollExtent;
  final double viewportExtent;
  final ContinuousImageScrollDirection userScrollDirection;
  final bool isScrollActivityInProgress;
}

class ContinuousImageScrollCompensationPlan {
  const ContinuousImageScrollCompensationPlan._({
    required this.timing,
    required this.delta,
    required this.targetOffset,
    required this.reason,
  });

  factory ContinuousImageScrollCompensationPlan.none([String reason = 'none']) {
    return ContinuousImageScrollCompensationPlan._(
      timing: ContinuousImageScrollCompensationTiming.none,
      delta: 0,
      targetOffset: 0,
      reason: reason,
    );
  }

  factory ContinuousImageScrollCompensationPlan.immediate({
    required double delta,
    required double targetOffset,
  }) {
    return ContinuousImageScrollCompensationPlan._(
      timing: ContinuousImageScrollCompensationTiming.immediate,
      delta: delta,
      targetOffset: targetOffset,
      reason: 'immediate',
    );
  }

  factory ContinuousImageScrollCompensationPlan.deferred({
    required double delta,
    required double targetOffset,
  }) {
    return ContinuousImageScrollCompensationPlan._(
      timing: ContinuousImageScrollCompensationTiming.deferred,
      delta: delta,
      targetOffset: targetOffset,
      reason: 'deferredUntilIdle',
    );
  }

  final ContinuousImageScrollCompensationTiming timing;
  final double delta;
  final double targetOffset;
  final String reason;

  bool get shouldCompensate =>
      timing != ContinuousImageScrollCompensationTiming.none;

  bool get shouldApplyImmediately =>
      timing == ContinuousImageScrollCompensationTiming.immediate;

  bool get shouldDefer =>
      timing == ContinuousImageScrollCompensationTiming.deferred;
}

class ContinuousImageScrollAnchorCoordinator {
  const ContinuousImageScrollAnchorCoordinator({
    this.changeThreshold = 0.5,
    this.deferWhileScrolling = true,
    this.layoutResolver = const ContinuousImageLayoutResolver(),
  }) : assert(changeThreshold >= 0);

  final double changeThreshold;
  final bool deferWhileScrolling;
  final ContinuousImageLayoutResolver layoutResolver;

  ContinuousImageScrollCompensationPlan planForExtentChange({
    required ContinuousImageExtent? previousExtent,
    required ContinuousImageExtent nextExtent,
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required ContinuousImageFlowPolicy policy,
    required ContinuousImageScrollAnchorMetrics metrics,
  }) {
    if (!policy.allowScrollOffsetCompensation) {
      return ContinuousImageScrollCompensationPlan.none('policyDisabled');
    }
    if (previousExtent == null) {
      return ContinuousImageScrollCompensationPlan.none('noPreviousExtent');
    }
    if (previousExtent.ownerId != nextExtent.ownerId ||
        previousExtent.itemId != nextExtent.itemId) {
      return ContinuousImageScrollCompensationPlan.none('differentItem');
    }
    final delta = nextExtent.mainAxisExtent - previousExtent.mainAxisExtent;
    if (delta.abs() <= changeThreshold) {
      return ContinuousImageScrollCompensationPlan.none('belowThreshold');
    }
    final itemPosition = items.indexWhere(
      (item) => item.id == nextExtent.itemId,
    );
    if (itemPosition < 0) {
      return ContinuousImageScrollCompensationPlan.none('itemNotFound');
    }
    final itemStartOffset = extentRegistry.estimateOffsetForIndex(
      itemPosition,
      items,
      crossAxisExtent: nextExtent.crossAxisExtent,
      resolver: layoutResolver,
    );
    final previousItemEndOffset =
        itemStartOffset + previousExtent.mainAxisExtent;
    if (previousItemEndOffset > metrics.scrollOffset) {
      return ContinuousImageScrollCompensationPlan.none('notAboveViewport');
    }

    final targetOffset = (metrics.scrollOffset + delta)
        .clamp(metrics.minScrollExtent, metrics.maxScrollExtent)
        .toDouble();
    if ((targetOffset - metrics.scrollOffset).abs() <= changeThreshold) {
      return ContinuousImageScrollCompensationPlan.none(
        'clampedBelowThreshold',
      );
    }
    if (deferWhileScrolling &&
        (metrics.isScrollActivityInProgress ||
            metrics.userScrollDirection !=
                ContinuousImageScrollDirection.idle)) {
      return ContinuousImageScrollCompensationPlan.deferred(
        delta: delta,
        targetOffset: targetOffset,
      );
    }
    return ContinuousImageScrollCompensationPlan.immediate(
      delta: delta,
      targetOffset: targetOffset,
    );
  }
}
