part of 'thread_post_native_flow.dart';

final class _ThreadInlineProbe {
  _ThreadInlineProbe(this.anchor, this.before, this.position)
    : pixels = position.pixels {
    position.addListener(_cancel);
    position.isScrollingNotifier.addListener(_scrolling);
  }

  final ForumBodyFlowTextAnchor anchor;
  final Rect before;
  final ScrollPosition position;
  final double pixels;
  bool done = false;
  bool _cancelled = false;
  double? newTop;
  ForumBodyFlowPreparedSlice? slice;

  bool isAt(ScrollPosition candidate) =>
      !_cancelled &&
      identical(candidate, position) &&
      position.pixels == pixels &&
      !position.isScrollingNotifier.value;

  ForumBodyFlowPreparedSlice? takeSlice() {
    final result = slice;
    slice = null;
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
  }
}

extension on _ThreadPostNativeFlowState {
  _ThreadInlineProbe? _beginInlineProbe(
    _ThreadFlowRun old,
    _ThreadFlowRun next,
    ScrollPosition position,
  ) {
    final window = ForumBodyFlowBox.borrowPaintedTextWindow(old.boundsKey);
    if (window == null) return null;
    final point = ForumBodyFlowTextAnchor.firstVisible(window);
    if (point == null) return null;
    final probe = next.inlineProbe = _ThreadInlineProbe(
      point.anchor,
      point.bounds,
      position,
    );
    unawaited(_measureInlineProbe(old, next, probe));
    return probe;
  }

  Future<void> _measureInlineProbe(
    _ThreadFlowRun old,
    _ThreadFlowRun next,
    _ThreadInlineProbe probe,
  ) async {
    final session = next.session!;
    bool current() =>
        _current(next) &&
        identical(_shown, old) &&
        identical(next.inlineProbe, probe) &&
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
        final page = prefix[index];
        if (page.table == null &&
            page.fragments.any(probe.anchor.matchesHint)) {
          final job = session.openPagePreparation(index);
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
              snapshot: prefix,
              page: index,
              fragments: fragments,
            );
            if (bounds != null) {
              probe.newTop = next.pageTops[index] + bounds.top;
              probe.slice = ForumBodyFlowPreparedSlice(
                session: session,
                index: index,
                fragments: fragments,
              );
              fragments = const [];
              return;
            }
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
      if (_current(next) && identical(next.inlineProbe, probe)) {
        probe.done = true;
        _present(next);
      } else {
        probe.takeSlice()?.close();
      }
    }
  }
}
