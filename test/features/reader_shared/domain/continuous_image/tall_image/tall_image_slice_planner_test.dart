import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  group('TallImageSlicePlanner', () {
    const planner = TallImageSlicePlanner();

    test('returns null when policy is disabled', () {
      final manifest = planner.plan(
        originalItemId: 'page-1',
        originalCacheKey: 'cache/page-1',
        imageWidth: 1000,
        imageHeight: 8000,
        viewportMainAxisExtent: 1000,
        policy: TallImagePolicy.disabled,
      );

      expect(manifest, isNull);
    });

    test('returns null for non tall images', () {
      final manifest = planner.plan(
        originalItemId: 'page-1',
        originalCacheKey: 'cache/page-1',
        imageWidth: 1000,
        imageHeight: 2500,
        viewportMainAxisExtent: 1000,
        policy: TallImagePolicy.mihonLike,
      );

      expect(manifest, isNull);
    });

    test('plans Mihon-like slices for tall images', () {
      final manifest = planner.plan(
        originalItemId: 'page-1',
        originalCacheKey: 'cache/page-1',
        imageWidth: 1000,
        imageHeight: 5500,
        viewportMainAxisExtent: 1000,
        policy: TallImagePolicy.mihonLike,
      );

      expect(manifest, isNotNull);
      expect(manifest!.originalItemId, 'page-1');
      expect(manifest.originalCacheKey, 'cache/page-1');
      expect(manifest.targetSliceHeight, 2000);
      expect(manifest.partCount, 3);
      expect(manifest.slices.map((slice) => slice.top), <int>[0, 2000, 4000]);
      expect(manifest.slices.map((slice) => slice.height), <int>[
        2000,
        2000,
        1500,
      ]);
      expect(manifest.slices.map((slice) => slice.cacheKey), <String>[
        'cache/page-1#slice-0',
        'cache/page-1#slice-1',
        'cache/page-1#slice-2',
      ]);
    });

    test('exposes stable aspect ratios for manifest and slices', () {
      final manifest = planner.plan(
        originalItemId: 'page-1',
        originalCacheKey: 'cache/page-1',
        imageWidth: 1000,
        imageHeight: 5000,
        viewportMainAxisExtent: 1000,
        policy: TallImagePolicy.mihonLike,
      );

      expect(manifest!.originalAspectRatio, 0.2);
      expect(manifest.slices.first.aspectRatio, 0.5);
      expect(manifest.slices.last.aspectRatio, 1);
    });
  });
}
