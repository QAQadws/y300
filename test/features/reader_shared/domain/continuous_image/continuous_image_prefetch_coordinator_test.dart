import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  group('ContinuousImagePrefetchCoordinator', () {
    const coordinator = ContinuousImagePrefetchCoordinator();
    const policy = ContinuousImageFlowPolicy(
      prefetchWindowBefore: 1,
      prefetchWindowAfter: 3,
    );

    test('returns empty plan for empty item list', () {
      final plan = coordinator.windowForIndex(
        focusIndex: 4,
        itemCount: 0,
        policy: policy,
      );

      expect(plan.focusIndex, isNull);
      expect(plan.indices, isEmpty);
    });

    test('clamps focus and prefetch window to item bounds', () {
      final plan = coordinator.windowForIndex(
        focusIndex: 20,
        itemCount: 5,
        policy: policy,
      );

      expect(plan.focusIndex, 4);
      expect(plan.indices, <int>[4, 3]);
    });

    test('prioritizes forward indices for forward or idle scrolling', () {
      final plan = coordinator.windowForIndex(
        focusIndex: 3,
        itemCount: 10,
        policy: policy,
        scrollDirection: ContinuousImageScrollDirection.forward,
      );

      expect(plan.indices, <int>[3, 4, 5, 6, 2]);
    });

    test('prioritizes backward indices for reverse scrolling', () {
      final plan = coordinator.windowForIndex(
        focusIndex: 3,
        itemCount: 10,
        policy: policy,
        scrollDirection: ContinuousImageScrollDirection.reverse,
      );

      expect(plan.indices, <int>[3, 2, 4, 5, 6]);
    });

    test('can omit visible item when caller only wants neighbors', () {
      final plan = coordinator.windowForIndex(
        focusIndex: 3,
        itemCount: 10,
        policy: policy,
        includeVisible: false,
      );

      expect(plan.indices, <int>[4, 5, 6, 2]);
    });

    test('uses last end visible index as viewport focus', () {
      final plan = coordinator.windowForViewport(
        viewport: const ContinuousImageViewportState(
          firstVisibleIndex: 1,
          lastVisibleIndex: 2,
          lastEndVisibleIndex: 3,
          scrollOffset: 400,
          viewportExtent: 800,
          userScrollDirection: ContinuousImageScrollDirection.forward,
        ),
        itemCount: 10,
        policy: policy,
      );

      expect(plan.focusIndex, 3);
      expect(plan.indices, <int>[3, 4, 5, 6, 2]);
    });

    test('maps planned indices to items and keep ids', () {
      final items = List<ContinuousImageItem>.generate(
        5,
        (index) => _item(index),
      );
      final plan = coordinator.windowForIndex(
        focusIndex: 2,
        itemCount: items.length,
        policy: policy,
      );

      expect(plan.itemsFrom(items).map((item) => item.id), <String>[
        'page-2',
        'page-3',
        'page-4',
        'page-1',
      ]);
      expect(plan.keepItemIdsFrom(items), <String>{
        'page-1',
        'page-2',
        'page-3',
        'page-4',
      });
    });
  });
}

ContinuousImageItem _item(int index) {
  return ContinuousImageItem(
    ownerId: 'chapter-1',
    id: 'page-$index',
    url: 'https://img.test/$index.jpg',
    cacheKey: 'cache-$index',
    index: index,
    sourceKind: ContinuousImageSourceKind.comicPage,
  );
}
