part of 'thread_post_native_flow.dart';

typedef _ThreadTableSource = ({
  String path,
  String areaPath,
  ForumBodyTableVisibleWindow window,
  double insetX,
});

typedef _ThreadTableResult = ({
  int index,
  double offset,
  ForumBodyTablePreparedSlice slice,
});

typedef _ThreadSourceCandidate = ({
  ForumBodyTextPageSnapshot snapshot,
  int page,
  ForumBodyTableAreaLayout? area,
});

final class _ThreadSourceReflowProbe {
  _ThreadSourceReflowProbe(this.anchor, this.before, this.position, this.table)
    : pixels = position.pixels {
    position.addListener(_cancel);
    position.isScrollingNotifier.addListener(_scrolling);
  }

  final ForumBodyFlowSourceAnchor anchor;
  final Rect before;
  final ScrollPosition position;
  final double pixels;
  final _ThreadTableSource? table;
  bool done = false;
  bool _cancelled = false;
  double? newTop;
  ForumBodyFlowPreparedSlice? slice;
  _ThreadTableResult? tableResult;

  bool isAt(ScrollPosition candidate) =>
      !_cancelled &&
      identical(candidate, position) &&
      position.pixels == pixels &&
      !position.isScrollingNotifier.value &&
      (table?.window.isCurrent ?? true);

  ForumBodyFlowPreparedSlice? takeSlice() {
    final result = slice;
    slice = null;
    return result;
  }

  _ThreadTableResult? takeTable() {
    final result = tableResult;
    tableResult = null;
    return result;
  }

  void _scrolling() {
    if (position.isScrollingNotifier.value) _cancel();
  }

  void _cancel() => _cancelled = true;

  void close() {
    _cancel();
    position.removeListener(_cancel);
    position.isScrollingNotifier.removeListener(_scrolling);
    takeSlice()?.close();
    takeTable()?.slice.close();
  }
}

extension on _ThreadPostNativeFlowState {
  _ThreadSourceReflowProbe? _beginSourceProbe(
    _ThreadFlowRun old,
    _ThreadFlowRun next,
    ScrollPosition position,
  ) {
    final window = ForumBodyFlowBox.borrowPaintedTextWindow(old.boundsKey);
    ({ForumBodyFlowSourceAnchor anchor, Rect bounds})? point = window == null
        ? null
        : ForumBodyFlowTextAnchor.firstVisible(window);
    _ThreadTableSource? table;
    for (final entry in old.tableWindows.entries) {
      final frame = old.prefix![entry.key].table!;
      final tableTop = old.pageTops[entry.key] + frame.bounds.top;
      if (point != null && tableTop >= point.bounds.top) continue;
      final ({ForumBodyFlowSourceAnchor anchor, Rect bounds, String areaPath})?
      hit =
          ForumBodyFlowTextAnchor.firstVisibleInTable(entry.value) ??
          ForumBodyFlowImageAnchor.firstVisibleInTable(entry.value);
      if (hit == null) continue;
      final bounds = hit.bounds.shift(
        Offset(frame.bounds.left - entry.value.bounds.left, tableTop),
      );
      if (point != null && point.bounds.top <= bounds.top) continue;
      point = (anchor: hit.anchor, bounds: bounds);
      table = (
        path: frame.path,
        areaPath: hit.areaPath,
        window: entry.value,
        insetX: hit.bounds.left - entry.value.bounds.left,
      );
    }
    if (point == null) return null;
    final probe = next.sourceProbe = _ThreadSourceReflowProbe(
      point.anchor,
      point.bounds,
      position,
      table,
    );
    unawaited(_measureSourceProbe(old, next, probe));
    return probe;
  }

  Future<void> _measureSourceProbe(
    _ThreadFlowRun old,
    _ThreadFlowRun next,
    _ThreadSourceReflowProbe probe,
  ) async {
    final session = next.session!;
    bool current() =>
        _current(next) &&
        identical(_shown, old) &&
        identical(next.sourceProbe, probe) &&
        !session.isClosed &&
        !session.isLayoutOwnerRetired &&
        probe.isAt(probe.position);
    final clock = Stopwatch();
    var frames = 0, index = 0;
    Future<void> nextFrame() async {
      frames++;
      WidgetsBinding.instance.ensureVisualUpdate();
      await WidgetsBinding.instance.endOfFrame;
      clock.reset();
      clock.start();
    }

    try {
      await nextFrame();
      while (current() && frames < 48) {
        final prefix = next.prefix!;
        if (index >= prefix.length) {
          if (prefix.isComplete) return;
          await nextFrame();
          continue;
        }
        for (final target in _sourceCandidates(session, prefix, index, probe)) {
          if (clock.elapsedMicroseconds >= 2200) await nextFrame();
          if (!current() || frames >= 48) return;
          if (target == null) continue;
          final area = target.area;
          final job = area == null
              ? session.openPagePreparation(index)
              : area.openPagePreparation(target.page);
          var fragments = const <ForumBodyPreparedTextFragment>[];
          try {
            while (!job.isReady && current() && frames < 48) {
              var steps = 0;
              while (!job.isReady &&
                  steps++ < 6 &&
                  clock.elapsedMicroseconds < 2200) {
                final step = job.advance(maxFragments: 2, maxParts: 8);
                if (step.waitingForLayoutBudget) break;
              }
              if (!job.isReady) await nextFrame();
            }
            if (!current() || !job.isReady) return;
            fragments = job.takeFragments();
            final bounds = probe.anchor.locate(
              snapshot: target.snapshot,
              page: target.page,
              fragments: fragments,
            );
            if (bounds == null) continue;
            if (area == null) {
              probe.newTop = next.pageTops[index] + bounds.top;
              probe.slice = ForumBodyFlowPreparedSlice(
                session: session,
                index: index,
                fragments: fragments,
              );
            } else {
              final frame = prefix[index].table!;
              if (bounds.width > frame.bounds.width) continue;
              final tableBounds = bounds.shift(
                area.contentBounds.topLeft +
                    Offset(0, area.pageTop(target.page)),
              );
              probe.newTop =
                  next.pageTops[index] + frame.bounds.top + tableBounds.top;
              probe.tableResult = (
                index: index,
                offset: (tableBounds.left - probe.table!.insetX).clamp(
                  0.0,
                  math.max(0.0, frame.contentSize.width - frame.bounds.width),
                ),
                slice: ForumBodyTablePreparedSlice(
                  area: area,
                  page: target.page,
                  fragments: fragments,
                ),
              );
            }
            fragments = const [];
            return;
          } finally {
            for (final fragment in fragments) {
              fragment.close();
            }
            job.close();
          }
        }
        index++;
        if (clock.elapsedMicroseconds >= 2200) await nextFrame();
      }
    } on Object {
      // A view-budget or owner change cannot make the sealed body unreadable.
    } finally {
      if (_current(next) && identical(next.sourceProbe, probe)) {
        probe.done = true;
        _present(next);
      } else {
        probe.close();
      }
    }
  }
}

Iterable<_ThreadSourceCandidate?> _sourceCandidates(
  ForumBodyTextPageSession session,
  ForumBodyTextPageSnapshot prefix,
  int index,
  _ThreadSourceReflowProbe probe,
) sync* {
  final page = prefix[index];
  final source = probe.table;
  if (source == null) {
    if (page.table == null && page.fragments.any(probe.anchor.matchesHint)) {
      yield (snapshot: prefix, page: index, area: null);
    }
    return;
  }
  if (page.table?.path != source.path) return;
  final table = session.tableLayoutForPage(index)!;
  for (final area in table.captions.followedBy(table.cells)) {
    yield null;
    if (area.element.path != source.areaPath) continue;
    final snapshot = area.snapshot;
    for (final slice in snapshot) {
      yield slice.fragments.any(probe.anchor.matchesHint)
          ? (snapshot: snapshot, page: slice.index, area: area)
          : null;
    }
    return;
  }
}
