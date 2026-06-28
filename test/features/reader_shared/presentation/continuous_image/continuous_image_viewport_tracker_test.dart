import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';

void main() {
  group('ContinuousImageViewportTracker', () {
    const tracker = ContinuousImageViewportTracker();

    test('resolves visible range from recorded and estimated extents', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <ContinuousImageItem>[
        _item(0, spacingAfter: 10),
        _item(1, spacingAfter: 10),
        _item(2, spacingAfter: 10),
      ];
      registry
        ..record(_extent(index: 0, height: 300))
        ..record(_extent(index: 1, height: 400));

      final viewport = tracker.resolve(
        items: items,
        extentRegistry: registry,
        scrollOffset: 320,
        viewportExtent: 450,
        crossAxisExtent: 300,
        userScrollDirection: ContinuousImageScrollDirection.forward,
      );

      expect(viewport.firstVisibleIndex, 1);
      expect(viewport.lastVisibleIndex, 2);
      expect(viewport.lastEndVisibleIndex, 1);
      expect(viewport.scrollOffset, 320);
      expect(viewport.viewportExtent, 450);
      expect(
        viewport.userScrollDirection,
        ContinuousImageScrollDirection.forward,
      );
    });

    test('uses fallback dimensions when no recorded extent exists', () {
      final viewport = tracker.resolve(
        items: <ContinuousImageItem>[
          _item(0, fallbackAspectRatio: 1, spacingAfter: 10),
          _item(1, fallbackAspectRatio: 1),
        ],
        extentRegistry: InMemoryContinuousImageExtentRegistry(),
        scrollOffset: 250,
        viewportExtent: 200,
        crossAxisExtent: 300,
        userScrollDirection: ContinuousImageScrollDirection.idle,
      );

      expect(viewport.firstVisibleIndex, 0);
      expect(viewport.lastVisibleIndex, 1);
      expect(viewport.lastEndVisibleIndex, 0);
    });

    test('maps Flutter scroll directions to reading directions', () {
      expect(
        tracker.directionFromFlutter(ScrollDirection.reverse),
        ContinuousImageScrollDirection.forward,
      );
      expect(
        tracker.directionFromFlutter(ScrollDirection.forward),
        ContinuousImageScrollDirection.reverse,
      );
      expect(
        tracker.directionFromFlutter(ScrollDirection.idle),
        ContinuousImageScrollDirection.idle,
      );
    });
  });
}

ContinuousImageItem _item(
  int index, {
  double fallbackAspectRatio = 0.7,
  double spacingAfter = 0,
}) {
  return ContinuousImageItem(
    ownerId: 'chapter-1',
    id: 'page-$index',
    url: 'https://img.test/$index.jpg',
    cacheKey: 'page-$index',
    index: index,
    sourceKind: ContinuousImageSourceKind.comicPage,
    fallbackAspectRatio: fallbackAspectRatio,
    spacingAfter: spacingAfter,
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
