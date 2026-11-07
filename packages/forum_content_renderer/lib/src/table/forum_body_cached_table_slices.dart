part of 'forum_body_table_viewport.dart';

/// Shares the viewport's cell/page intersection rules with the mount transfer.
Iterable<_Slice> _tableSlicesIn(
  ForumBodyTableLayout layout,
  Rect window, {
  VoidCallback? beforeVisit,
}) sync* {
  for (final area in layout.captions.followedBy(layout.cells)) {
    beforeVisit?.call();
    if (!area.contentBounds.overlaps(window)) continue;
    final snapshot = area.snapshot;
    var start = 0;
    var end = snapshot.length;
    while (start < end) {
      final mid = (start + end) ~/ 2;
      final bottom =
          area.contentBounds.top + area.pageTop(mid) + snapshot[mid].usedHeight;
      if (bottom <= window.top) {
        start = mid + 1;
      } else {
        end = mid;
      }
    }
    for (var page = start; page < snapshot.length; page++) {
      beforeVisit?.call();
      final top = area.contentBounds.top + area.pageTop(page);
      if (top >= window.bottom) break;
      if (snapshot[page].usedHeight > 0) yield (area: area, page: page);
    }
  }
}

final class _CachedTableUnavailable implements Exception {
  const _CachedTableUnavailable();
}

final class _CachedTableSlices {
  _CachedTableSlices(this.timeBudget, this.remainingSteps);

  final Duration timeBudget;
  int remainingSteps;
  final _clock = Stopwatch();
  final _slices = <ForumBodyTablePreparedSlice>[];

  List<ForumBodyTablePreparedSlice>? prepare(
    Iterable<({ForumBodyTableLayout layout, Rect bounds})> windows,
  ) {
    _clock.start();
    var transferred = false;
    try {
      for (final window in windows) {
        _visit(window.layout, window.bounds);
      }
      transferred = true;
      return List.unmodifiable(_slices);
    } on _CachedTableUnavailable {
      return null;
    } finally {
      if (!transferred) {
        for (final slice in _slices) {
          slice.close();
        }
      }
    }
  }

  void _checkBudget() {
    if (remainingSteps-- <= 0 || _clock.elapsed >= timeBudget) {
      throw const _CachedTableUnavailable();
    }
  }

  void _visit(ForumBodyTableLayout layout, Rect bounds) {
    _checkBudget();
    if (layout.isClosed) throw const _CachedTableUnavailable();
    if (bounds.isEmpty) return;
    for (final slice in _tableSlicesIn(
      layout,
      bounds,
      beforeVisit: _checkBudget,
    )) {
      final work = slice.area.openPagePreparation(slice.page);
      try {
        while (true) {
          _checkBudget();
          if (work.tryPrepareCached(maxParts: 32)) break;
          if (work.cacheMiss || work.waitingForLayoutBudget) {
            throw const _CachedTableUnavailable();
          }
        }
        _slices.add(
          ForumBodyTablePreparedSlice(
            area: slice.area,
            page: slice.page,
            fragments: work.takeFragments(),
          ),
        );
      } finally {
        work.close();
      }
      final origin =
          slice.area.contentBounds.topLeft +
          Offset(0, slice.area.pageTop(slice.page));
      for (final frame in slice.area.snapshot[slice.page].tableFrames) {
        _checkBudget();
        final clip = bounds.shift(-origin).intersect(frame.bounds);
        if (clip.isEmpty) continue;
        final nested = slice.area.tableLayoutForPage(
          slice.page,
          path: frame.path,
        );
        if (nested == null) throw StateError('Missing nested table layout');
        final offset = slice.area.flowTableOffset(slice.page, frame.path) ?? 0;
        _visit(nested, clip.shift(-frame.bounds.topLeft + Offset(offset, 0)));
      }
    }
  }
}
