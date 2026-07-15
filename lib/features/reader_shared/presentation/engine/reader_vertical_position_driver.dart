import 'dart:async';

enum ReaderVerticalSeekStatus { exact, estimated, cancelled, unavailable }

enum ReaderVerticalSeekCancelReason {
  superseded,
  userScroll,
  ownerChanged,
  modeChanged,
  disposed,
}

class ReaderVerticalSeekResult {
  const ReaderVerticalSeekResult({
    required this.status,
    required this.index,
    required this.elapsed,
    required this.correctionDelta,
    required this.correctionPasses,
    this.cancelReason,
  });

  final ReaderVerticalSeekStatus status;
  final int index;
  final Duration elapsed;
  final double correctionDelta;
  final int correctionPasses;
  final ReaderVerticalSeekCancelReason? cancelReason;

  bool get reached =>
      status == ReaderVerticalSeekStatus.exact ||
      status == ReaderVerticalSeekStatus.estimated;
  bool get exact => status == ReaderVerticalSeekStatus.exact;
}

typedef ReaderVerticalOffsetResolver = double? Function(int index);
typedef ReaderVerticalLayoutWaiter = Future<void> Function();

/// Drives vertical index seeks without retaining any list or widget state.
///
/// The engine supplies an estimated offset and an exact RenderViewport anchor
/// resolver. A request is generation-like: starting another seek or receiving
/// an explicit user drag cancels the pending correction immediately.
class ReaderVerticalPositionDriver {
  ReaderVerticalPositionDriver({
    required bool Function() isReady,
    required double Function() currentOffset,
    required double Function(double offset) clampOffset,
    required void Function(double offset) jumpTo,
    required ReaderVerticalOffsetResolver estimateOffset,
    required ReaderVerticalOffsetResolver exactOffset,
    required ReaderVerticalLayoutWaiter waitForLayout,
    this.maxCorrectionPasses = 4,
    this.correctionThreshold = 0.5,
  }) : _isReady = isReady,
       _currentOffset = currentOffset,
       _clampOffset = clampOffset,
       _jumpTo = jumpTo,
       _estimateOffset = estimateOffset,
       _exactOffset = exactOffset,
       _waitForLayout = waitForLayout,
       assert(maxCorrectionPasses > 0),
       assert(correctionThreshold >= 0);

  final bool Function() _isReady;
  final double Function() _currentOffset;
  final double Function(double offset) _clampOffset;
  final void Function(double offset) _jumpTo;
  final ReaderVerticalOffsetResolver _estimateOffset;
  final ReaderVerticalOffsetResolver _exactOffset;
  final ReaderVerticalLayoutWaiter _waitForLayout;
  final int maxCorrectionPasses;
  final double correctionThreshold;

  _ActiveVerticalSeek? _active;
  bool _disposed = false;

  bool get hasActiveSeek => _active != null;

  Future<ReaderVerticalSeekResult> seekToIndex(int index) async {
    cancelActive(ReaderVerticalSeekCancelReason.superseded);
    final stopwatch = Stopwatch()..start();
    if (_disposed || !_isReady()) {
      return ReaderVerticalSeekResult(
        status: ReaderVerticalSeekStatus.unavailable,
        index: index,
        elapsed: stopwatch.elapsed,
        correctionDelta: 0,
        correctionPasses: 0,
      );
    }

    final request = _ActiveVerticalSeek(index);
    _active = request;
    final directOffset = _exactOffset(index);
    if (directOffset != null) {
      final target = _clampOffset(directOffset);
      _jumpIfNeeded(target);
      return _finish(
        request,
        status: ReaderVerticalSeekStatus.exact,
        stopwatch: stopwatch,
        correctionDelta: 0,
        correctionPasses: 0,
      );
    }

    var estimatedOffset = _clampOffset(_estimateOffset(index) ?? 0);
    _jumpIfNeeded(estimatedOffset);
    for (var pass = 1; pass <= maxCorrectionPasses; pass++) {
      await Future.any<void>(<Future<void>>[
        _waitForLayout(),
        request.cancelled.future,
      ]);
      final cancelled = _cancelledResult(request, stopwatch, pass - 1);
      if (cancelled != null) {
        return cancelled;
      }
      if (!_isReady()) {
        return _finish(
          request,
          status: ReaderVerticalSeekStatus.unavailable,
          stopwatch: stopwatch,
          correctionDelta: 0,
          correctionPasses: pass,
        );
      }

      final exactOffset = _exactOffset(index);
      if (exactOffset != null) {
        final correctedOffset = _clampOffset(exactOffset);
        final correctionDelta = correctedOffset - estimatedOffset;
        _jumpIfNeeded(correctedOffset);
        return _finish(
          request,
          status: ReaderVerticalSeekStatus.exact,
          stopwatch: stopwatch,
          correctionDelta: correctionDelta,
          correctionPasses: pass,
        );
      }

      final refined = _estimateOffset(index);
      if (refined != null && refined.isFinite) {
        estimatedOffset = _clampOffset(refined);
        _jumpIfNeeded(estimatedOffset);
      }
    }

    return _finish(
      request,
      status: ReaderVerticalSeekStatus.estimated,
      stopwatch: stopwatch,
      correctionDelta: 0,
      correctionPasses: maxCorrectionPasses,
    );
  }

  bool cancelActive(ReaderVerticalSeekCancelReason reason) {
    final active = _active;
    if (active == null) {
      return false;
    }
    active.cancel(reason);
    return true;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    cancelActive(ReaderVerticalSeekCancelReason.disposed);
  }

  void _jumpIfNeeded(double target) {
    if ((_currentOffset() - target).abs() > correctionThreshold) {
      _jumpTo(target);
    }
  }

  ReaderVerticalSeekResult? _cancelledResult(
    _ActiveVerticalSeek request,
    Stopwatch stopwatch,
    int correctionPasses,
  ) {
    if (identical(_active, request) && request.cancelReason == null) {
      return null;
    }
    return _finish(
      request,
      status: ReaderVerticalSeekStatus.cancelled,
      stopwatch: stopwatch,
      correctionDelta: 0,
      correctionPasses: correctionPasses,
      cancelReason:
          request.cancelReason ?? ReaderVerticalSeekCancelReason.superseded,
    );
  }

  ReaderVerticalSeekResult _finish(
    _ActiveVerticalSeek request, {
    required ReaderVerticalSeekStatus status,
    required Stopwatch stopwatch,
    required double correctionDelta,
    required int correctionPasses,
    ReaderVerticalSeekCancelReason? cancelReason,
  }) {
    stopwatch.stop();
    if (identical(_active, request)) {
      _active = null;
    }
    return ReaderVerticalSeekResult(
      status: status,
      index: request.index,
      elapsed: stopwatch.elapsed,
      correctionDelta: correctionDelta,
      correctionPasses: correctionPasses,
      cancelReason: cancelReason,
    );
  }
}

class _ActiveVerticalSeek {
  _ActiveVerticalSeek(this.index);

  final int index;
  final Completer<void> cancelled = Completer<void>();
  ReaderVerticalSeekCancelReason? cancelReason;

  void cancel(ReaderVerticalSeekCancelReason reason) {
    cancelReason ??= reason;
    if (!cancelled.isCompleted) {
      cancelled.complete();
    }
  }
}
