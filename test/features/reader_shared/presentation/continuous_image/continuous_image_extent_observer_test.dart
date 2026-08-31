import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_extent_observer.dart';

void main() {
  testWidgets('ContinuousImageExtentObserver reports laid out extent', (
    tester,
  ) async {
    final extents = <ContinuousImageExtent>[];
    const item = ContinuousImageItem(
      ownerId: 'chapter-1',
      id: 'image-1',
      url: 'https://img.test/1.jpg',
      cacheKey: 'image-1',
      index: 2,
      sourceKind: ContinuousImageSourceKind.comicPage,
    );

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Center(
          child: ContinuousImageExtentObserver(
            item: item,
            aspectRatio: 0.5,
            dimensionSource: ContinuousImageDimensionSource.persistedCache,
            onExtentResolved: extents.add,
            child: const SizedBox(width: 120, height: 240),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(extents, hasLength(1));
    expect(extents.single.ownerId, 'chapter-1');
    expect(extents.single.itemId, 'image-1');
    expect(extents.single.index, 2);
    expect(extents.single.crossAxisExtent, 120);
    expect(extents.single.mainAxisExtent, 240);
    expect(extents.single.aspectRatio, 0.5);
    expect(
      extents.single.dimensionSource,
      ContinuousImageDimensionSource.persistedCache,
    );
  });
}
