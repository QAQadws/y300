final class ReaderSeekRequest {
  ReaderSeekRequest._({
    required this.generation,
    required this.targetIndex,
    required this.locksSlider,
    required bool Function() isSurfaceCurrent,
  }) : _isSurfaceCurrent = isSurfaceCurrent;

  final int generation;
  final int targetIndex;
  final bool locksSlider;
  final bool Function() _isSurfaceCurrent;
}

/// Owns preview, commit throttling and request identity independently of widgets.
final class ReaderSeekCoordinator {
  ReaderSeekCoordinator({
    this.commitInterval = const Duration(milliseconds: 120),
  });

  final Duration commitInterval;
  ReaderSeekRequest? _active;
  int _generation = 0;
  int? _previewIndex;
  DateTime? _lastCommitAt;
  bool _closed = false;

  int get generation => _generation;
  int? get previewIndex => _previewIndex;
  bool get isSliderLocked => _active?.locksSlider ?? false;
  int? get pendingIndex => isSliderLocked ? _active?.targetIndex : null;

  void preview(int? index) {
    if (!_closed) _previewIndex = index;
  }

  ReaderSeekRequest? beginSlider({
    required int targetIndex,
    required bool Function() isSurfaceCurrent,
    required DateTime now,
  }) {
    if (_closed || !isSurfaceCurrent()) return null;
    final lastCommitAt = _lastCommitAt;
    if (lastCommitAt != null && now.difference(lastCommitAt) < commitInterval) {
      return null;
    }
    _lastCommitAt = now;
    _previewIndex = targetIndex;
    return _begin(targetIndex, isSurfaceCurrent, locksSlider: true);
  }

  ReaderSeekRequest? beginModeChange({
    required int targetIndex,
    required bool Function() isSurfaceCurrent,
  }) {
    if (_closed || !isSurfaceCurrent()) return null;
    _previewIndex = null;
    return _begin(targetIndex, isSurfaceCurrent, locksSlider: false);
  }

  ReaderSeekRequest _begin(
    int targetIndex,
    bool Function() isSurfaceCurrent, {
    required bool locksSlider,
  }) => _active = ReaderSeekRequest._(
    generation: ++_generation,
    targetIndex: targetIndex,
    locksSlider: locksSlider,
    isSurfaceCurrent: isSurfaceCurrent,
  );

  bool isCurrent(ReaderSeekRequest request) =>
      !_closed && identical(_active, request) && request._isSurfaceCurrent();

  /// An old completion must never unlock a newer request, even for the same owner.
  bool finish(ReaderSeekRequest request) {
    if (!identical(_active, request)) return false;
    _active = null;
    _previewIndex = null;
    return true;
  }

  void reset({bool resetThrottle = true}) {
    _active = null;
    _previewIndex = null;
    if (resetThrottle) _lastCommitAt = null;
  }

  void close() {
    _closed = true;
    reset();
  }
}
