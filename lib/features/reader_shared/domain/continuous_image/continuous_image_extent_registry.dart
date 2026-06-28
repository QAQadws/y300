import 'continuous_image_layout_resolver.dart';
import 'continuous_image_models.dart';

abstract interface class ContinuousImageExtentRegistry {
  ContinuousImageExtent? extentOf(String itemId);

  double estimateOffsetForIndex(
    int index,
    List<ContinuousImageItem> items, {
    required double crossAxisExtent,
    ContinuousImageLayoutResolver resolver =
        const ContinuousImageLayoutResolver(),
  });

  void record(ContinuousImageExtent extent);

  void clearForOwner(String ownerId);
}

class InMemoryContinuousImageExtentRegistry
    implements ContinuousImageExtentRegistry {
  InMemoryContinuousImageExtentRegistry();

  final Map<String, ContinuousImageExtent> _extentsById =
      <String, ContinuousImageExtent>{};

  @override
  ContinuousImageExtent? extentOf(String itemId) {
    return _extentsById[itemId];
  }

  @override
  double estimateOffsetForIndex(
    int index,
    List<ContinuousImageItem> items, {
    required double crossAxisExtent,
    ContinuousImageLayoutResolver resolver =
        const ContinuousImageLayoutResolver(),
  }) {
    if (items.isEmpty || index <= 0 || crossAxisExtent <= 0) {
      return 0;
    }
    final end = index.clamp(0, items.length);
    var offset = 0.0;
    for (final item in items.take(end)) {
      final recorded = extentOf(item.id);
      offset +=
          recorded?.mainAxisExtent ??
          _estimateMainAxisExtent(
            item: item,
            crossAxisExtent: crossAxisExtent,
            resolver: resolver,
          );
      offset += item.spacingAfter;
    }
    return offset;
  }

  @override
  void record(ContinuousImageExtent extent) {
    _extentsById[extent.itemId] = extent;
  }

  @override
  void clearForOwner(String ownerId) {
    _extentsById.removeWhere((_, extent) => extent.ownerId == ownerId);
  }

  double _estimateMainAxisExtent({
    required ContinuousImageItem item,
    required double crossAxisExtent,
    required ContinuousImageLayoutResolver resolver,
  }) {
    final hint = resolver.resolveInitialHint(item: item);
    return crossAxisExtent / hint.aspectRatio;
  }
}
