import 'dart:collection';

/// Frame-end observations of a block-image occurrence, independent of loading
/// and decode admission. Identities are immutable values and are never exported.
abstract interface class ForumHtmlImageVisibilityObserver {
  void observe(
    Object identity, {
    required bool visible,
    required bool painted,
    required bool failed,
  });

  /// Ends an occurrence's current visit, preserving bounded revisit history.
  void retire(Object identity);
}

/// Bounded, owner-scoped outcome metrics. A visit starts on the first sampled
/// Flutter frame with positive clipped viewport intersection. A first-frame hit
/// requires painted pixels on that frame; disk/decode completion is insufficient.
/// This measures Flutter paint/compositing readiness, not GPU presentation time.
final class ForumHtmlImageVisibilityMetrics
    implements ForumHtmlImageVisibilityObserver {
  ForumHtmlImageVisibilityMetrics({
    this.historyCapacity = 512,
    this.activeCapacity = 128,
    int waitSampleCapacity = 256,
    Duration Function()? elapsed,
  }) : assert(historyCapacity > 0),
       assert(activeCapacity > 0),
       assert(waitSampleCapacity > 0),
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedDuration,
       _waits = _WaitSamples(waitSampleCapacity),
       _revisitWaits = _WaitSamples(waitSampleCapacity),
       _failureWaits = _WaitSamples(waitSampleCapacity),
       _abandonedWaits = _WaitSamples(waitSampleCapacity);

  final int historyCapacity;
  final int activeCapacity;
  final Duration Function() _elapsed;
  final _seen = <Object, bool>{};
  final _active = <Object, _Visit>{};
  final _WaitSamples _waits, _revisitWaits, _failureWaits, _abandonedWaits;
  int _entries = 0, _revisits = 0, _hits = 0, _revisitHits = 0;
  int _completed = 0, _failed = 0, _abandoned = 0;
  int _historyEvictions = 0, _droppedObservations = 0;
  bool _closed = false;

  @override
  void observe(
    Object identity, {
    required bool visible,
    required bool painted,
    required bool failed,
  }) {
    if (_closed) return;
    if (!visible) {
      retire(identity);
      return;
    }
    var visit = _active[identity];
    final enteredNow = visit == null;
    if (visit == null) {
      if (_active.length >= activeCapacity) {
        _droppedObservations++;
        return;
      }
      visit = _Visit(_elapsed(), _seen.containsKey(identity));
      _active[identity] = visit;
      _entries++;
      if (visit.revisit) _revisits++;
      if (painted) {
        _hits++;
        if (visit.revisit) _revisitHits++;
      }
    }
    if (painted) {
      _seen.remove(identity);
      _seen[identity] = true;
      if (_seen.length > historyCapacity) {
        _seen.remove(_seen.keys.first);
        _historyEvictions++;
      }
    }
    if (visit.settled) return;
    if (painted) {
      visit.settled = true;
      _completed++;
      final wait = enteredNow ? Duration.zero : _elapsed() - visit.entered;
      _waits.add(wait);
      if (visit.revisit) _revisitWaits.add(wait);
    } else if (failed) {
      visit.settled = true;
      _failed++;
      _failureWaits.add(_elapsed() - visit.entered);
    }
  }

  @override
  void retire(Object identity) {
    final visit = _active.remove(identity);
    if (visit != null && !visit.settled) {
      _abandoned++;
      _abandonedWaits.add(_elapsed() - visit.entered);
    }
  }

  /// Closing is permanent; late observations cannot populate a new owner.
  void close() {
    if (_closed) return;
    for (final identity in _active.keys.toList(growable: false)) {
      retire(identity);
    }
    _closed = true;
    _seen.clear();
  }

  ForumHtmlImageVisibilitySnapshot get snapshot {
    final pending = _active.values.where((visit) => !visit.settled);
    final now = _elapsed();
    var oldest = Duration.zero;
    for (final visit in pending) {
      final wait = now - visit.entered;
      if (wait > oldest) oldest = wait;
    }
    return ForumHtmlImageVisibilitySnapshot._({
      'entries': _entries,
      'firstFrameHits': _hits,
      'revisitEntries': _revisits,
      'revisitFirstFrameHits': _revisitHits,
      'revisitFirstFrameHitRatio': _revisits == 0
          ? null
          : _revisitHits / _revisits,
      'completed': _completed,
      'failed': _failed,
      'abandoned': _abandoned,
      'pending': pending.length,
      'oldestPendingWaitMs': oldest.inMicroseconds / 1000,
      'historyEntries': _seen.length,
      'historyEvictions': _historyEvictions,
      'droppedObservations': _droppedObservations,
      'successfulWaits': _waits.snapshot,
      'successfulRevisitWaits': _revisitWaits.snapshot,
      'failureWaits': _failureWaits.snapshot,
      'abandonedWaits': _abandonedWaits.snapshot,
    });
  }
}

/// Numeric summaries only; no image identities, paths, URLs or content.
final class ForumHtmlImageVisibilitySnapshot {
  ForumHtmlImageVisibilitySnapshot._(Map<String, Object?> values)
    : values = Map.unmodifiable(values);

  final Map<String, Object?> values;
  Map<String, Object?> toJson() => values;
}

final class _Visit {
  _Visit(this.entered, this.revisit);
  final Duration entered;
  final bool revisit;
  bool settled = false;
}

final class _WaitSamples {
  _WaitSamples(this.capacity);
  final int capacity;
  final _samples = Queue<int>();

  void add(Duration wait) {
    if (_samples.length == capacity) _samples.removeFirst();
    _samples.add(wait.inMicroseconds.clamp(0, 1 << 62));
  }

  Map<String, Object?> get snapshot {
    final sorted = _samples.toList()..sort();
    double? percentile(double fraction) => sorted.isEmpty
        ? null
        : sorted[(sorted.length * fraction).ceil() - 1] / 1000;
    return Map.unmodifiable({
      'recentSamples': sorted.length,
      'p50Ms': percentile(0.5),
      'p95Ms': percentile(0.95),
      'p99Ms': percentile(0.99),
    });
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}
