import 'package:continuous_image_geometry/continuous_image_geometry.dart';
import 'package:test/test.dart';

import 'fixtures/geometry_test_item.dart';

void main() {
  group('ContinuousImageLayoutResolver', () {
    const resolver = ContinuousImageLayoutResolver();
    final item = _item(knownWidth: 1200, knownHeight: 1800);

    test('uses html dimensions before persisted dimensions', () {
      final hint = resolver.resolveInitialHint(
        item: item,
        htmlDimensions: const ContinuousImageDimensionCandidate(
          width: 800,
          height: 1000,
          source: ContinuousImageDimensionSource.html,
        ),
        persistedDimensions: const ContinuousImageDimensionCandidate(
          width: 1200,
          height: 1800,
          source: ContinuousImageDimensionSource.persistedCache,
        ),
      );

      expect(hint.source, ContinuousImageDimensionSource.html);
      expect(hint.aspectRatio, 0.8);
    });

    test('uses persisted dimensions before item fallback dimensions', () {
      final hint = resolver.resolveInitialHint(
        item: item,
        persistedDimensions: const ContinuousImageDimensionCandidate(
          width: 900,
          height: 1800,
          source: ContinuousImageDimensionSource.persistedCache,
        ),
      );

      expect(hint.source, ContinuousImageDimensionSource.persistedCache);
      expect(hint.aspectRatio, 0.5);
    });

    test('uses item known dimensions when no explicit hints exist', () {
      final hint = resolver.resolveInitialHint(item: item);

      expect(hint.source, ContinuousImageDimensionSource.persistedCache);
      expect(hint.aspectRatio, closeTo(1200 / 1800, 0.0001));
    });

    test('falls back when all dimensions are invalid', () {
      final hint = resolver.resolveInitialHint(
        item: _item(knownWidth: -1, knownHeight: 0, fallbackAspectRatio: 0.72),
        htmlDimensions: const ContinuousImageDimensionCandidate(
          width: 0,
          height: 1000,
          source: ContinuousImageDimensionSource.html,
        ),
        persistedDimensions: const ContinuousImageDimensionCandidate(
          width: 1000,
          height: -1,
          source: ContinuousImageDimensionSource.persistedCache,
        ),
      );

      expect(hint.source, ContinuousImageDimensionSource.fallback);
      expect(hint.aspectRatio, 0.72);
    });

    test('decoded hint is ignored when dimensions are invalid', () {
      expect(resolver.resolveDecodedHint(width: 0, height: 100), isNull);
      expect(
        resolver.resolveDecodedHint(width: 1600, height: 800)?.aspectRatio,
        2,
      );
    });
  });

  group('InMemoryContinuousImageExtentRegistry', () {
    test('estimates offsets with recorded extents and fallback hints', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      final items = <GeometryTestItem>[
        _item(id: 'a', knownWidth: 1000, knownHeight: 2000, spacingAfter: 10),
        _item(id: 'b', knownWidth: 800, knownHeight: 400, spacingAfter: 6),
        _item(id: 'c', fallbackAspectRatio: 1),
      ];
      registry.record(
        ContinuousImageExtent(
          ownerId: 'chapter-1',
          itemId: 'a',
          index: 0,
          crossAxisExtent: 300,
          mainAxisExtent: 500,
          aspectRatio: 0.6,
          dimensionSource: ContinuousImageDimensionSource.decodedImage,
          measuredAt: DateTime(2026),
        ),
      );

      final offset = registry.estimateOffsetForIndex(
        2,
        items,
        crossAxisExtent: 300,
      );

      expect(offset, 500 + 10 + 150 + 6);
    });

    test('clears extents by owner', () {
      final registry = InMemoryContinuousImageExtentRegistry();
      registry
        ..record(
          ContinuousImageExtent(
            ownerId: 'one',
            itemId: 'a',
            index: 0,
            crossAxisExtent: 300,
            mainAxisExtent: 500,
            aspectRatio: 0.6,
            dimensionSource: ContinuousImageDimensionSource.decodedImage,
            measuredAt: DateTime(2026),
          ),
        )
        ..record(
          ContinuousImageExtent(
            ownerId: 'two',
            itemId: 'b',
            index: 0,
            crossAxisExtent: 300,
            mainAxisExtent: 500,
            aspectRatio: 0.6,
            dimensionSource: ContinuousImageDimensionSource.decodedImage,
            measuredAt: DateTime(2026),
          ),
        );

      registry.clearForOwner('one');

      expect(registry.extentOf('a'), isNull);
      expect(registry.extentOf('b'), isNotNull);
    });

    test(
      'item IDs replace owner records without resizing measured extents',
      () {
        final registry = InMemoryContinuousImageExtentRegistry();
        final item = _item(
          id: 'shared-image',
          knownWidth: 1000,
          knownHeight: 2000,
          spacingAfter: 10,
        );
        registry.record(
          ContinuousImageExtent(
            ownerId: 'one',
            itemId: item.id,
            index: 0,
            crossAxisExtent: 300,
            mainAxisExtent: 500,
            aspectRatio: 0.6,
            dimensionSource: ContinuousImageDimensionSource.decodedImage,
            measuredAt: DateTime(2026),
          ),
        );
        final replacement = ContinuousImageExtent(
          ownerId: 'two',
          itemId: item.id,
          index: 0,
          crossAxisExtent: 300,
          mainAxisExtent: 240,
          aspectRatio: 1.25,
          dimensionSource: ContinuousImageDimensionSource.decodedImage,
          measuredAt: DateTime(2026),
        );
        registry.record(replacement);
        registry.clearForOwner('one');
        expect(registry.extentOf(item.id), same(replacement));
        for (final width in <double>[300, 600]) {
          expect(
            registry.estimateOffsetForIndex(1, [item], crossAxisExtent: width),
            250,
          );
        }

        // Only the Host's next measurement replaces the stored physical height.
        registry.clearForOwner('two');
        expect(
          registry.estimateOffsetForIndex(1, [item], crossAxisExtent: 600),
          1210,
        );
      },
    );
  });
}

GeometryTestItem _item({
  String id = 'image-1',
  int? knownWidth,
  int? knownHeight,
  double fallbackAspectRatio = 0.7,
  double spacingAfter = 0,
}) {
  return GeometryTestItem(
    ownerId: 'chapter-1',
    id: id,
    index: 0,
    knownWidth: knownWidth,
    knownHeight: knownHeight,
    fallbackAspectRatio: fallbackAspectRatio,
    spacingAfter: spacingAfter,
  );
}
