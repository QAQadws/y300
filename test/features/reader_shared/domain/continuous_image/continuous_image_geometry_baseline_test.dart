import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  test(
    'long mixed sequences agree on seek prefixes and inclusive visibility',
    () {
      const width = 360.0;
      final fixture = _mixedSequence(1000, width: width);
      final reference = _scanGeometry(fixture.items, fixture.heights);
      final layout = ContinuousImageLayoutIndex(
        items: fixture.items,
        extentRegistry: fixture.registry,
        crossAxisExtent: width,
      );

      _expectSeekPrefixes(fixture.items, fixture.registry, reference, width);
      for (var position = 0; position < reference.rows.length; position++) {
        final row = reference.rows[position];
        final viewport = position % 7 == 0
            ? 0.0
            : 110.0 + (position % 9) * 57.5;
        for (final offset in <double>[
          row.start - 0.25,
          row.start,
          row.end,
          row.end + 0.25,
        ]) {
          _expectViewport(layout, reference, offset, viewport);
        }
      }
      _expectViewport(layout, reference, -20, 800);
      _expectViewport(layout, reference, reference.total + 1, 800);
    },
  );

  test('measurement changes and owner clearing replace geometry snapshots', () {
    const width = 360.0;
    final fixture = _mixedSequence(40, width: width);
    final before = _scanGeometry(fixture.items, fixture.heights);
    final original = ContinuousImageLayoutIndex(
      items: fixture.items,
      extentRegistry: fixture.registry,
      crossAxisExtent: width,
    );
    final foreignItem = _item(0, owner: 'other-chapter');
    final foreignExtent = _extent(foreignItem, width, 900);
    fixture.registry.record(foreignExtent);

    final changedHeights = List<double>.of(fixture.heights);
    changedHeights[5] += 137.5;
    fixture.registry.record(
      _extent(fixture.items[5], width, changedHeights[5]),
    );
    final changed = _scanGeometry(fixture.items, changedHeights);
    final replacement = ContinuousImageLayoutIndex(
      items: fixture.items,
      extentRegistry: fixture.registry,
      crossAxisExtent: width,
    );

    // An index is a layout snapshot; the Host replaces it after an extent write.
    _expectGeometrySamples(original, before);
    _expectGeometrySamples(replacement, changed);
    _expectSeekPrefixes(fixture.items, fixture.registry, changed, width);

    fixture.registry.clearForOwner('chapter');
    final cleared = _scanGeometry(fixture.items, fixture.estimatedHeights);
    final afterClear = ContinuousImageLayoutIndex(
      items: fixture.items,
      extentRegistry: fixture.registry,
      crossAxisExtent: width,
    );
    _expectGeometrySamples(original, before);
    _expectGeometrySamples(replacement, changed);
    _expectGeometrySamples(afterClear, cleared);
    _expectSeekPrefixes(fixture.items, fixture.registry, cleared, width);
    expect(fixture.registry.extentOf(foreignItem.id), same(foreignExtent));
  });

  test(
    'successive above-viewport size corrections preserve reading position',
    () {
      const width = 360.0;
      const targetPosition = 28;
      const withinImage = 37.5;
      const coordinator = ContinuousImageScrollAnchorCoordinator();
      final items = List<ContinuousImageItem>.generate(
        40,
        (position) => _item(position, spacing: (position % 3) * 2.5),
      );
      final heights = List<double>.generate(
        items.length,
        (position) => 300.0 + (position % 4) * 50,
      );
      final registry = InMemoryContinuousImageExtentRegistry();
      for (var position = 0; position < items.length; position++) {
        registry.record(_extent(items[position], width, heights[position]));
      }
      var reference = _scanGeometry(items, heights);
      var offset = reference.rows[targetPosition].start + withinImage;

      for (final change in <(int, double)>[
        (2, 175),
        (8, -125),
        (2, -80),
        (18, 235),
        (25, -140),
      ]) {
        final (position, delta) = change;
        final previous = registry.extentOf(items[position].id)!;
        final next = _extent(items[position], width, heights[position] + delta);
        final plan = coordinator.planForExtentChange(
          previousExtent: previous,
          nextExtent: next,
          items: items,
          extentRegistry: registry,
          policy: const ContinuousImageFlowPolicy(
            allowScrollOffsetCompensation: true,
          ),
          metrics: ContinuousImageScrollAnchorMetrics(
            scrollOffset: offset,
            minScrollExtent: 0,
            maxScrollExtent: reference.total,
            viewportExtent: 100,
            userScrollDirection: ContinuousImageScrollDirection.idle,
          ),
        );
        expect(plan.shouldApplyImmediately, isTrue);
        expect(plan.delta, delta);
        registry.record(next);
        heights[position] += delta;
        reference = _scanGeometry(items, heights);
        offset = plan.targetOffset;

        expect(offset, reference.rows[targetPosition].start + withinImage);
        expect(
          registry.estimateOffsetForIndex(
            targetPosition,
            items,
            crossAxisExtent: width,
          ),
          reference.rows[targetPosition].start,
        );
        final layout = ContinuousImageLayoutIndex(
          items: items,
          extentRegistry: registry,
          crossAxisExtent: width,
        );
        _expectViewport(layout, reference, offset, 100);
        expect(
          layout
              .resolve(
                scrollOffset: offset,
                viewportExtent: 100,
                userScrollDirection: ContinuousImageScrollDirection.idle,
              )
              .firstVisibleIndex,
          items[targetPosition].index,
        );
      }
    },
  );

  test(
    'touching image ends preserve the compensation and threshold boundary',
    () {
      const width = 360.0;
      const coordinator = ContinuousImageScrollAnchorCoordinator();
      final items = <ContinuousImageItem>[_item(0), _item(1)];
      final registry = InMemoryContinuousImageExtentRegistry();
      final previous = _extent(items.first, width, 120);
      registry.record(previous);
      final layout = ContinuousImageLayoutIndex(
        items: items,
        extentRegistry: registry,
        crossAxisExtent: width,
      );
      expect(
        layout
            .resolve(
              scrollOffset: 120,
              viewportExtent: 20,
              userScrollDirection: ContinuousImageScrollDirection.idle,
            )
            .firstVisibleIndex,
        items.first.index,
      );

      ContinuousImageScrollCompensationPlan plan(
        double delta, {
        double max = 1000,
      }) {
        return coordinator.planForExtentChange(
          previousExtent: previous,
          nextExtent: _extent(items.first, width, 120 + delta),
          items: items,
          extentRegistry: registry,
          policy: const ContinuousImageFlowPolicy(
            allowScrollOffsetCompensation: true,
          ),
          metrics: ContinuousImageScrollAnchorMetrics(
            scrollOffset: 120,
            minScrollExtent: 0,
            maxScrollExtent: max,
            viewportExtent: 20,
            userScrollDirection: ContinuousImageScrollDirection.idle,
          ),
        );
      }

      expect(plan(0.5).reason, 'belowThreshold');
      expect(plan(-0.5).reason, 'belowThreshold');
      final correction = plan(0.75);
      expect(correction.shouldApplyImmediately, isTrue);
      expect(correction.targetOffset, 120.75);
      expect(plan(5, max: 120.5).reason, 'clampedBelowThreshold');
    },
  );
}

typedef _GeometryRow = ({int index, double start, double end});
typedef _ReferenceGeometry = ({List<_GeometryRow> rows, double total});

({
  List<ContinuousImageItem> items,
  List<double> heights,
  List<double> estimatedHeights,
  InMemoryContinuousImageExtentRegistry registry,
})
_mixedSequence(int count, {required double width}) {
  final items = <ContinuousImageItem>[];
  final heights = <double>[];
  final estimatedHeights = <double>[];
  final registry = InMemoryContinuousImageExtentRegistry();
  for (var position = 0; position < count; position++) {
    final knownHeight = position % 3 == 0 ? 120 * (1 << (position % 4)) : null;
    final ratio = 0.5 * (1 << (position % 3));
    final item = _item(
      position,
      knownHeight: knownHeight,
      fallbackRatio: ratio,
      spacing: (position % 4) * 2.5,
    );
    final estimated = knownHeight == null
        ? width / ratio
        : width * knownHeight / 240;
    final measured = position % 5 == 0
        ? (position % 25 == 0 ? 0.0 : 40.0 + (position % 17) * 37.5)
        : null;
    items.add(item);
    estimatedHeights.add(estimated);
    heights.add(measured ?? estimated);
    if (measured != null) {
      registry.record(_extent(item, width, measured));
    }
  }
  return (
    items: items,
    heights: heights,
    estimatedHeights: estimatedHeights,
    registry: registry,
  );
}

ContinuousImageItem _item(
  int position, {
  String owner = 'chapter',
  int? knownHeight,
  double fallbackRatio = 1,
  double spacing = 0,
}) => ContinuousImageItem(
  ownerId: owner,
  id: '$owner-image-$position',
  url: '',
  cacheKey: '$owner-image-$position',
  index: 20 + position * 3,
  sourceKind: ContinuousImageSourceKind.comicPage,
  knownWidth: knownHeight == null ? null : 240,
  knownHeight: knownHeight,
  fallbackAspectRatio: fallbackRatio,
  spacingAfter: spacing,
);

ContinuousImageExtent _extent(
  ContinuousImageItem item,
  double width,
  double height,
) => ContinuousImageExtent(
  ownerId: item.ownerId,
  itemId: item.id,
  index: item.index,
  crossAxisExtent: width,
  mainAxisExtent: height,
  aspectRatio: height == 0 ? 1 : width / height,
  dimensionSource: ContinuousImageDimensionSource.decodedImage,
  measuredAt: DateTime(2026),
);

// Expected heights come from the fixture, independent of resolver/registry code.
_ReferenceGeometry _scanGeometry(
  List<ContinuousImageItem> items,
  List<double> heights,
) {
  final rows = <_GeometryRow>[];
  var cursor = 0.0;
  for (var position = 0; position < items.length; position++) {
    final end = cursor + heights[position];
    rows.add((index: items[position].index, start: cursor, end: end));
    cursor = end + items[position].spacingAfter;
  }
  return (rows: rows, total: cursor);
}

void _expectSeekPrefixes(
  List<ContinuousImageItem> items,
  InMemoryContinuousImageExtentRegistry registry,
  _ReferenceGeometry reference,
  double width,
) {
  for (var position = 0; position <= items.length; position++) {
    // estimateOffsetForIndex takes the sequence position, not item.index.
    final expected = position == items.length
        ? reference.total
        : reference.rows[position].start;
    expect(
      registry.estimateOffsetForIndex(position, items, crossAxisExtent: width),
      expected,
      reason: 'seek prefix at sequence position $position',
    );
  }
  expect(registry.estimateOffsetForIndex(-1, items, crossAxisExtent: width), 0);
  expect(
    registry.estimateOffsetForIndex(
      items.length + 10,
      items,
      crossAxisExtent: width,
    ),
    reference.total,
  );
}

void _expectGeometrySamples(
  ContinuousImageLayoutIndex layout,
  _ReferenceGeometry reference,
) {
  for (final row in reference.rows) {
    _expectViewport(layout, reference, row.start, 120);
    _expectViewport(layout, reference, row.end + 0.25, 120);
  }
}

void _expectViewport(
  ContinuousImageLayoutIndex layout,
  _ReferenceGeometry reference,
  double offset,
  double viewport,
) {
  final start = offset < 0 ? 0.0 : offset;
  final end = start + viewport;
  final visible = <int>[];
  final ended = <int>[];
  if (viewport > 0) {
    for (final row in reference.rows) {
      if (row.end >= start && row.start <= end) visible.add(row.index);
      if (row.end >= start && row.end <= end) ended.add(row.index);
    }
  }
  final actual = layout.resolve(
    scrollOffset: offset,
    viewportExtent: viewport,
    userScrollDirection: ContinuousImageScrollDirection.reverse,
  );
  expect(
    (
      actual.firstVisibleIndex,
      actual.lastVisibleIndex,
      actual.lastEndVisibleIndex,
    ),
    (visible.firstOrNull, visible.lastOrNull, ended.lastOrNull),
    reason: 'viewport [$start, $end], extent $viewport',
  );
  expect(actual.scrollOffset, start);
  expect(actual.viewportExtent, viewport);
  expect(actual.userScrollDirection, ContinuousImageScrollDirection.reverse);
}
