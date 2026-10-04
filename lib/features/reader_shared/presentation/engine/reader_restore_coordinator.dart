/// A restore attempt remains valid only for its captured position and surface.
final class ReaderRestoreRequest {
  ReaderRestoreRequest._(this.generation, this._isSurfaceCurrent);

  final int generation;
  final bool Function() _isSurfaceCurrent;
}

/// Serializes initial restores while Flutter attachment and seeking stay hosted.
final class ReaderRestoreCoordinator {
  ReaderRestoreRequest? _active;
  int _generation = 0;
  bool _closed = false;

  ReaderRestoreRequest? begin({required bool Function() isSurfaceCurrent}) {
    if (_closed || !isSurfaceCurrent()) return null;
    final active = _active;
    if (active != null && active._isSurfaceCurrent()) return null;
    return _active = ReaderRestoreRequest._(++_generation, isSurfaceCurrent);
  }

  bool isCurrent(ReaderRestoreRequest request) =>
      !_closed && identical(_active, request) && request._isSurfaceCurrent();

  void finish(ReaderRestoreRequest request) {
    if (identical(_active, request)) _active = null;
  }

  void invalidate() => _active = null;

  void close() {
    _closed = true;
    invalidate();
  }
}
