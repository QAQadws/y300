import 'continuous_image_extent_registry.dart';
import 'continuous_image_layout_resolver.dart';
import 'continuous_image_models.dart';

/// Geometry for one image layout, independent of its current scroll offset.
/// Rebuild when items, measured extents or viewport width change, then query
/// in logarithmic time while scrolling through images and arbitrary tail rows.
class ContinuousImageLayoutIndex {
  ContinuousImageLayoutIndex({
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required double crossAxisExtent,
    ContinuousImageLayoutResolver resolver =
        const ContinuousImageLayoutResolver(),
  }) {
    if (!crossAxisExtent.isFinite || crossAxisExtent <= 0) return;
    var cursor = 0.0;
    for (final item in items) {
      final extent =
          extentRegistry.extentOf(item.id)?.mainAxisExtent ??
          crossAxisExtent / resolver.resolveInitialHint(item: item).aspectRatio;
      _indexes.add(item.index);
      _starts.add(cursor);
      _ends.add(cursor + extent);
      cursor += extent + item.spacingAfter;
    }
  }

  final List<int> _indexes = [];
  final List<double> _starts = [];
  final List<double> _ends = [];

  ContinuousImageViewportState resolve({
    required double scrollOffset,
    required double viewportExtent,
    required ContinuousImageScrollDirection userScrollDirection,
  }) {
    final start = scrollOffset.clamp(0, double.infinity).toDouble();
    final end = start + viewportExtent;
    int? firstVisible;
    int? lastVisible;
    int? lastEndVisible;
    if (_indexes.isNotEmpty && viewportExtent > 0 && start <= _ends.last) {
      final first = _lowerBound(_ends, start);
      final last = _upperBound(_starts, end) - 1;
      if (first <= last && first < _indexes.length && last >= 0) {
        firstVisible = _indexes[first];
        lastVisible = _indexes[last];
      }
      final lastEnd = _upperBound(_ends, end) - 1;
      if (lastEnd >= 0 && _ends[lastEnd] >= start) {
        lastEndVisible = _indexes[lastEnd];
      }
    }
    return ContinuousImageViewportState(
      firstVisibleIndex: firstVisible,
      lastVisibleIndex: lastVisible,
      lastEndVisibleIndex: lastEndVisible,
      scrollOffset: start,
      viewportExtent: viewportExtent.clamp(0, double.infinity).toDouble(),
      userScrollDirection: userScrollDirection,
    );
  }

  static int _lowerBound(List<double> values, double target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (values[middle] < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static int _upperBound(List<double> values, double target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (values[middle] <= target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
