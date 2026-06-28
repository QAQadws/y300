import 'continuous_image_models.dart';

class ContinuousImagePrefetchPlan {
  const ContinuousImagePrefetchPlan({
    required this.focusIndex,
    required this.indices,
  });

  final int? focusIndex;
  final List<int> indices;

  Set<int> get keepIndexSet => indices.toSet();

  List<ContinuousImageItem> itemsFrom(List<ContinuousImageItem> items) {
    return indices
        .where((index) => index >= 0 && index < items.length)
        .map((index) => items[index])
        .toList(growable: false);
  }

  Set<String> keepItemIdsFrom(List<ContinuousImageItem> items) {
    return itemsFrom(items).map((item) => item.id).toSet();
  }
}

class ContinuousImagePrefetchCoordinator {
  const ContinuousImagePrefetchCoordinator();

  ContinuousImagePrefetchPlan windowForViewport({
    required ContinuousImageViewportState viewport,
    required int itemCount,
    required ContinuousImageFlowPolicy policy,
    bool includeVisible = true,
  }) {
    final focusIndex =
        viewport.lastEndVisibleIndex ??
        viewport.lastVisibleIndex ??
        viewport.firstVisibleIndex;
    if (focusIndex == null) {
      return const ContinuousImagePrefetchPlan(
        focusIndex: null,
        indices: <int>[],
      );
    }
    return windowForIndex(
      focusIndex: focusIndex,
      itemCount: itemCount,
      policy: policy,
      scrollDirection: viewport.userScrollDirection,
      includeVisible: includeVisible,
    );
  }

  ContinuousImagePrefetchPlan windowForIndex({
    required int focusIndex,
    required int itemCount,
    required ContinuousImageFlowPolicy policy,
    ContinuousImageScrollDirection scrollDirection =
        ContinuousImageScrollDirection.idle,
    bool includeVisible = true,
  }) {
    if (itemCount <= 0) {
      return const ContinuousImagePrefetchPlan(
        focusIndex: null,
        indices: <int>[],
      );
    }
    final clampedFocus = focusIndex.clamp(0, itemCount - 1).toInt();
    final beforeStart = (clampedFocus - policy.prefetchWindowBefore)
        .clamp(0, itemCount - 1)
        .toInt();
    final afterEnd = (clampedFocus + policy.prefetchWindowAfter)
        .clamp(0, itemCount - 1)
        .toInt();
    final indices = <int>[];
    if (includeVisible) {
      indices.add(clampedFocus);
    }

    void addForward() {
      for (var index = clampedFocus + 1; index <= afterEnd; index++) {
        indices.add(index);
      }
    }

    void addBackward() {
      for (var index = clampedFocus - 1; index >= beforeStart; index--) {
        indices.add(index);
      }
    }

    if (scrollDirection == ContinuousImageScrollDirection.reverse) {
      addBackward();
      addForward();
    } else {
      addForward();
      addBackward();
    }

    return ContinuousImagePrefetchPlan(
      focusIndex: clampedFocus,
      indices: indices.toSet().toList(growable: false),
    );
  }
}
