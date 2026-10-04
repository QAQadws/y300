import 'package:continuous_image_geometry/continuous_image_geometry.dart';
import 'package:test/test.dart';

import 'fixtures/geometry_test_item.dart';

void main() {
  group('ContinuousImageScrollAnchorCoordinator', () {
    const coordinator = ContinuousImageScrollAnchorCoordinator();

    test('compensates when an above-viewport item changes height', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <GeometryTestItem>[_item(0), _item(1), _item(2)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final plan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 380),
        items: items,
        extentRegistry: registry,
        allowScrollOffsetCompensation: true,
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
      final items = <GeometryTestItem>[_item(0), _item(1)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final plan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 380),
        items: items,
        extentRegistry: registry,
        allowScrollOffsetCompensation: true,
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
      final items = <GeometryTestItem>[_item(0), _item(1)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final plan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 240),
        items: items,
        extentRegistry: registry,
        allowScrollOffsetCompensation: true,
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
      final items = <GeometryTestItem>[_item(0), _item(1)];
      final previous = _extent(index: 0, height: 300);
      registry.record(previous);

      final disabledPlan = coordinator.planForExtentChange(
        previousExtent: previous,
        nextExtent: _extent(index: 0, height: 500),
        items: items,
        extentRegistry: registry,
        allowScrollOffsetCompensation: false,
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
        allowScrollOffsetCompensation: true,
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

GeometryTestItem _item(int index) {
  return GeometryTestItem(
    ownerId: 'chapter-1',
    id: 'page-$index',
    index: index,
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
