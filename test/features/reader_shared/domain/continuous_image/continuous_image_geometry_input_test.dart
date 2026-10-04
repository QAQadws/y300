import 'package:continuous_image_geometry/continuous_image_geometry.dart'
    as geometry;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  const resolver = geometry.ContinuousImageLayoutResolver();

  test(
    'Host known dimensions preserve their source through core resolution',
    () {
      for (final source in <geometry.ContinuousImageDimensionSource?>[
        null,
        geometry.ContinuousImageDimensionSource.html,
        geometry.ContinuousImageDimensionSource.decodedImage,
        geometry.ContinuousImageDimensionSource.probedHeader,
      ]) {
        final item = _item(knownWidth: 1200, knownHeight: 1800, source: source);
        final hint = resolver.resolveInitialHint(item: item);
        expect(item.knownDimensions?.width, 1200);
        expect(item.knownDimensions?.height, 1800);
        expect(hint.aspectRatio, closeTo(2 / 3, 0.000001));
        expect(
          hint.source,
          source ?? geometry.ContinuousImageDimensionSource.persistedCache,
        );
      }
    },
  );

  test('Host missing and invalid dimensions use the configured fallback', () {
    for (final dimensions in <(int?, int?)>[
      (null, null),
      (1200, null),
      (null, 1800),
      (0, 1800),
      (1200, 0),
      (-1, 1800),
      (1200, -1),
    ]) {
      final (width, height) = dimensions;
      final item = _item(
        knownWidth: width,
        knownHeight: height,
        source: geometry.ContinuousImageDimensionSource.html,
        fallbackRatio: 1.25,
      );
      expect(item.knownDimensions, isNull);
      final hint = resolver.resolveInitialHint(item: item);
      expect(hint.aspectRatio, 1.25);
      expect(hint.source, geometry.ContinuousImageDimensionSource.fallback);
    }
  });

  test('metadata-bearing copies work directly in an unchanged Host list', () {
    final referer = Uri.parse('https://example.test/thread/42');
    final metadata = <String, Object?>{'postId': 'post-7', 'protected': true};
    final original = ContinuousImageItem(
      ownerId: 'thread-42',
      id: 'original',
      url: 'https://img.test/attachment.jpg',
      cacheKey: 'protected-attachment',
      index: 4,
      sourceKind: ContinuousImageSourceKind.threadImageReader,
      referer: referer,
      knownWidth: 320,
      knownHeight: 640,
      knownDimensionSource:
          geometry.ContinuousImageDimensionSource.probedHeader,
      fallbackAspectRatio: 0.75,
      spacingAfter: 12,
      extra: metadata,
    );
    final updated = original.copyWith(
      id: 'updated',
      index: 9,
      knownWidth: 800,
      knownHeight: 400,
      knownDimensionSource:
          geometry.ContinuousImageDimensionSource.decodedImage,
      spacingAfter: 6,
    );
    final items = List<ContinuousImageItem>.unmodifiable([original, updated]);
    final registry = geometry.InMemoryContinuousImageExtentRegistry();
    final layout = geometry.ContinuousImageLayoutIndex(
      items: items,
      extentRegistry: registry,
      crossAxisExtent: 200,
    );
    final viewport = layout.resolve(
      scrollOffset: 420,
      viewportExtent: 100,
      userScrollDirection: geometry.ContinuousImageScrollDirection.forward,
    );
    expect(
      registry.estimateOffsetForIndex(1, items, crossAxisExtent: 200),
      412,
    );
    expect(
      registry.estimateOffsetForIndex(2, items, crossAxisExtent: 200),
      518,
    );
    expect(
      (
        viewport.firstVisibleIndex,
        viewport.lastVisibleIndex,
        viewport.lastEndVisibleIndex,
      ),
      (9, 9, 9),
    );
    expect(resolver.resolveInitialHint(item: updated).aspectRatio, 2);
    expect(
      resolver.resolveInitialHint(item: updated).source,
      geometry.ContinuousImageDimensionSource.decodedImage,
    );
    expect(original.knownDimensions?.height, 640);
    expect(updated.ownerId, original.ownerId);
    expect(updated.url, original.url);
    expect(updated.cacheKey, original.cacheKey);
    expect(updated.sourceKind, original.sourceKind);
    expect(updated.referer, same(referer));
    expect(updated.extra, same(metadata));
    expect(items[0], same(original));
    expect(items[1], same(updated));
  });
}

ContinuousImageItem _item({
  int? knownWidth,
  int? knownHeight,
  geometry.ContinuousImageDimensionSource? source,
  double fallbackRatio = 0.7,
}) => ContinuousImageItem(
  ownerId: 'chapter',
  id: 'image',
  url: 'https://img.test/image.jpg',
  cacheKey: 'image',
  index: 0,
  sourceKind: ContinuousImageSourceKind.comicPage,
  knownWidth: knownWidth,
  knownHeight: knownHeight,
  knownDimensionSource: source,
  fallbackAspectRatio: fallbackRatio,
);
