import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  group('ContinuousImageScrollAnchorCoordinator', () {
    const coordinator = ContinuousImageScrollAnchorCoordinator();
    const policy = ContinuousImageFlowPolicy(
      allowScrollOffsetCompensation: true,
    );

    test('compensates when an above-viewport item changes height', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <ContinuousImageItem>[_item(0), _item(1), _item(2)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final plan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 380),
        items: items,
        extentRegistry: registry,
        policy: policy,
        metrics: const ContinuousImageScrollAnchorMetrics(
          scrollOffset: 350,
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          viewportExtent: 600,
          userScrollDirection: ContinuousImageScrollDirection.idle,
        ),
      );

      expect(plan.shouldApplyImmediately, isTrue);
      expect(plan.delta, 80);
      expect(plan.targetOffset, 430);
    });

    test('does not compensate visible item height changes', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <ContinuousImageItem>[_item(0), _item(1)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final plan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 380),
        items: items,
        extentRegistry: registry,
        policy: policy,
        metrics: const ContinuousImageScrollAnchorMetrics(
          scrollOffset: 260,
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          viewportExtent: 600,
          userScrollDirection: ContinuousImageScrollDirection.idle,
        ),
      );

      expect(plan.shouldCompensate, isFalse);
      expect(plan.reason, 'notAboveViewport');
    });

    test('defers compensation while scrolling', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <ContinuousImageItem>[_item(0), _item(1)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final plan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 240),
        items: items,
        extentRegistry: registry,
        policy: policy,
        metrics: const ContinuousImageScrollAnchorMetrics(
          scrollOffset: 350,
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          viewportExtent: 600,
          userScrollDirection: ContinuousImageScrollDirection.reverse,
          isScrollActivityInProgress: true,
        ),
      );

      expect(plan.shouldDefer, isTrue);
      expect(plan.delta, -60);
      expect(plan.targetOffset, 290);
    });

    test('respects disabled policy and clamps target offset', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <ContinuousImageItem>[_item(0), _item(1)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final disabledPlan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 500),
        items: items,
        extentRegistry: registry,
        policy: const ContinuousImageFlowPolicy(
          allowScrollOffsetCompensation: false,
        ),
        metrics: const ContinuousImageScrollAnchorMetrics(
          scrollOffset: 350,
          minScrollExtent: 0,
          maxScrollExtent: 400,
          viewportExtent: 600,
          userScrollDirection: ContinuousImageScrollDirection.idle,
        ),
      );
      expect(disabledPlan.shouldCompensate, isFalse);

      final clampedPlan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 500),
        items: items,
        extentRegistry: registry,
        policy: policy,
        metrics: const ContinuousImageScrollAnchorMetrics(
          scrollOffset: 350,
          minScrollExtent: 0,
          maxScrollExtent: 400,
          viewportExtent: 600,
          userScrollDirection: ContinuousImageScrollDirection.idle,
        ),
      );
      expect(clampedPlan.shouldApplyImmediately, isTrue);
      expect(clampedPlan.targetOffset, 400);
    });
  });
}

ContinuousImageItem _item(int index) {
  return ContinuousImageItem(
    ownerId: 'chapter-1',
    id: 'page-$index',
    url: 'https://img.test/$index.jpg',
    cacheKey: 'page-$index',
    index: index,
    sourceKind: ContinuousImageSourceKind.comicPage,
    knownWidth: 300,
    knownHeight: 300,
  );
}

ContinuousImageExtent _extent({required int index, required double height}) {
  return ContinuousImageExtent(
    ownerId: 'chapter-1',
    itemId: 'page-$index',
    index: index,
    crossAxisExtent: 300,
    mainAxisExtent: height,
    aspectRatio: 300 / height,
    dimensionSource: ContinuousImageDimensionSource.decodedImage,
    measuredAt: DateTime(2026),
  );
}
