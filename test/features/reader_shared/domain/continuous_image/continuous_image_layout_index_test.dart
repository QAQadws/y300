import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  test('inclusive image edges, gaps and tail preserve progress semantics', () {
    final layout = ContinuousImageLayoutIndex(
      items: [_item(0, spacing: 10), _item(1, spacing: 10)],
      extentRegistry: InMemoryContinuousImageExtentRegistry(),
      crossAxisExtent: 100,
    );
    void check(double offset, double viewport, (int?, int?, int?) expected) {
      final result = layout.resolve(
        scrollOffset: offset,
        viewportExtent: viewport,
        userScrollDirection: ContinuousImageScrollDirection.forward,
      );
      expect((
        result.firstVisibleIndex,
        result.lastVisibleIndex,
        result.lastEndVisibleIndex,
      ), expected);
    }

    check(-10, 100, (0, 0, 0));
    check(100, 10, (0, 1, 0));
    check(101, 8, (null, null, null));
    check(110, 100, (1, 1, 1));
    check(210, 100, (1, 1, 1));
    check(211, 100, (null, null, null));
    check(0, 0, (null, null, null));
  });

  test(
    'binary queries match a linear reference over mixed measured heights',
    () {
      final random = Random(73);
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = List.generate(
        200,
        (i) => _item(i, spacing: random.nextDouble() * 48),
      );
      final starts = <double>[];
      final ends = <double>[];
      var cursor = 0.0;
      for (var i = 0; i < items.length; i++) {
        final height = i.isEven ? 80.0 + random.nextInt(1200) : 300.0;
        if (i.isEven) registry.record(_extent(i, height));
        starts.add(cursor);
        ends.add(cursor + height);
        cursor += height + items[i].spacingAfter;
      }
      final layout = ContinuousImageLayoutIndex(
        items: items,
        extentRegistry: registry,
        crossAxisExtent: 300,
      );
      for (var sample = 0; sample < 1000; sample++) {
        final offset = random.nextDouble() * (cursor + 1000);
        final viewport = 1.0 + random.nextInt(1600);
        final visible = [
          for (var i = 0; i < items.length; i++)
            if (ends[i] >= offset && starts[i] <= offset + viewport) i,
        ];
        final ended = [
          for (var i = 0; i < items.length; i++)
            if (ends[i] >= offset && ends[i] <= offset + viewport) i,
        ];
        final actual = layout.resolve(
          scrollOffset: offset,
          viewportExtent: viewport,
          userScrollDirection: ContinuousImageScrollDirection.reverse,
        );
        expect(actual.firstVisibleIndex, visible.firstOrNull);
        expect(actual.lastVisibleIndex, visible.lastOrNull);
        expect(actual.lastEndVisibleIndex, ended.lastOrNull);
      }
    },
  );

  for (final count in [20, 200, 1000]) {
    test(
      '$count images need no extent lookups while scrolling a built layout',
      () {
        final registry = _CountingRegistry();
        final items = List.generate(count, (i) => _item(i));
        final layout = ContinuousImageLayoutIndex(
          items: items,
          extentRegistry: registry,
          crossAxisExtent: 300,
        );
        expect(registry.reads, count);
        registry.reads = 0;
        for (var i = 0; i < 120; i++) {
          final viewport = layout.resolve(
            scrollOffset: count * 300.0 + i,
            viewportExtent: 600,
            userScrollDirection: ContinuousImageScrollDirection.forward,
          );
          if (i > 0) expect(viewport.firstVisibleIndex, isNull);
        }
        expect(registry.reads, 0);
      },
    );
  }

  test(
    'replacement layouts include measurements, width and spacing changes',
    () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = [_item(0), _item(1)];
      int? visible(
        List<ContinuousImageItem> items,
        double width,
        double offset,
      ) =>
          ContinuousImageLayoutIndex(
                items: items,
                extentRegistry: registry,
                crossAxisExtent: width,
              )
              .resolve(
                scrollOffset: offset,
                viewportExtent: 20,
                userScrollDirection: ContinuousImageScrollDirection.idle,
              )
              .firstVisibleIndex;
      expect(visible(items, 100, 150), 1);
      expect(visible(items, 200, 150), 0);
      expect(visible([_item(0, spacing: 80), _item(1)], 100, 150), isNull);
      registry.record(_extent(0, 400));
      expect(visible(items, 100, 150), 0);
      registry.clearForOwner('chapter');
      expect(visible(items, 100, 150), 1);
    },
  );
}

ContinuousImageItem _item(int i, {double spacing = 0}) => ContinuousImageItem(
  ownerId: 'chapter',
  id: 'image-$i',
  url: '',
  cacheKey: 'image-$i',
  index: i,
  sourceKind: ContinuousImageSourceKind.comicPage,
  fallbackAspectRatio: 1,
  spacingAfter: spacing,
);

ContinuousImageExtent _extent(int i, double height) => ContinuousImageExtent(
  ownerId: 'chapter',
  itemId: 'image-$i',
  index: i,
  crossAxisExtent: 300,
  mainAxisExtent: height,
  aspectRatio: 300 / height,
  dimensionSource: ContinuousImageDimensionSource.decodedImage,
  measuredAt: DateTime(2026),
);

class _CountingRegistry extends InMemoryContinuousImageExtentRegistry {
  int reads = 0;
  @override
  ContinuousImageExtent? extentOf(String itemId) {
    reads++;
    return super.extentOf(itemId);
  }
}
