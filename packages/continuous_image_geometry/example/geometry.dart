import 'package:continuous_image_geometry/continuous_image_geometry.dart';

void main() {
  const resolver = ContinuousImageLayoutResolver();
  const first = _LayoutItem(
    id: 'reader:image-0',
    index: 0,
    knownDimensions: ContinuousImageDimensions(width: 100, height: 100),
    spacingAfter: 10,
  );
  const second = _LayoutItem(
    id: 'reader:image-1',
    index: 1,
    effectiveKnownDimensionSource: ContinuousImageDimensionSource.fallback,
    fallbackAspectRatio: 1,
  );
  const items = <ContinuousImageLayoutItem>[first, second];
  final registry = InMemoryContinuousImageExtentRegistry();

  final initial = resolver.resolveInitialHint(
    item: first,
    htmlDimensions: const ContinuousImageDimensionCandidate(
      width: 200,
      height: 100,
      source: ContinuousImageDimensionSource.html,
    ),
  );
  print('Initial hint: ${initial.aspectRatio} (${initial.source.name})');
  final estimate = resolver.resolveInitialHint(item: second);
  print('Estimated hint: ${estimate.aspectRatio} (${estimate.source.name})');

  final layout = ContinuousImageLayoutIndex(
    items: items,
    extentRegistry: registry,
    crossAxisExtent: 100,
  );
  final edge = layout.resolve(
    scrollOffset: 100,
    viewportExtent: 10,
    userScrollDirection: ContinuousImageScrollDirection.idle,
  );
  final gap = layout.resolve(
    scrollOffset: 101,
    viewportExtent: 8,
    userScrollDirection: ContinuousImageScrollDirection.idle,
  );
  print('Inclusive edge: ${edge.firstVisibleIndex}..${edge.lastVisibleIndex}');
  print('Gap: ${gap.firstVisibleIndex}..${gap.lastVisibleIndex}');

  registry.record(
    ContinuousImageExtent(
      ownerId: 'reader',
      itemId: first.id,
      index: first.index,
      crossAxisExtent: 100,
      mainAxisExtent: 140,
      aspectRatio: 100 / 140,
      dimensionSource: ContinuousImageDimensionSource.decodedImage,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
  final updated =
      ContinuousImageLayoutIndex(
        items: items,
        extentRegistry: registry,
        crossAxisExtent: 100,
      ).resolve(
        scrollOffset: 120,
        viewportExtent: 10,
        userScrollDirection: ContinuousImageScrollDirection.idle,
      );
  print('Rebuilt after measurement: ${updated.firstVisibleIndex}');
}

final class _LayoutItem implements ContinuousImageLayoutItem {
  const _LayoutItem({
    required this.id,
    required this.index,
    this.knownDimensions,
    this.effectiveKnownDimensionSource =
        ContinuousImageDimensionSource.persistedCache,
    this.fallbackAspectRatio = 1,
    this.spacingAfter = 0,
  });

  @override
  final String id;

  @override
  final int index;

  @override
  final ContinuousImageDimensions? knownDimensions;

  @override
  final ContinuousImageDimensionSource effectiveKnownDimensionSource;

  @override
  final double fallbackAspectRatio;

  @override
  final double spacingAfter;
}
