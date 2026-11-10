import 'dart:async';

enum UnifiedDetailOperationKind {
  readingState,
  bookmark,
  download,
  readingReset,
}

/// A request belongs to one detail controller, including while a reset waits.
final class UnifiedDetailOperation {
  UnifiedDetailOperation._(this.kind, this.episodeId, this.predecessorsSettled);

  final UnifiedDetailOperationKind kind;
  final String? episodeId;
  final Future<void> predecessorsSettled;
  final _settled = Completer<void>();

  void _finish() {
    if (!_settled.isCompleted) _settled.complete();
  }
}

/// Internal operation ownership; persistence and result mapping stay in the host.
final class UnifiedDetailOperationCoordinator {
  final _active =
      <(UnifiedDetailOperationKind, String?), UnifiedDetailOperation>{};
  bool _closed = false;

  bool get isResettingReading =>
      isPending(UnifiedDetailOperationKind.readingReset);

  bool isPending(UnifiedDetailOperationKind kind, [String? episodeId]) =>
      _active.containsKey((kind, episodeId));

  UnifiedDetailOperation? beginChapter(
    UnifiedDetailOperationKind kind,
    String episodeId,
  ) {
    assert(kind != UnifiedDetailOperationKind.readingReset);
    if (_closed ||
        isPending(kind, episodeId) ||
        (kind == UnifiedDetailOperationKind.readingState &&
            isResettingReading)) {
      return null;
    }
    final request = UnifiedDetailOperation._(
      kind,
      episodeId,
      Future<void>.value(),
    );
    _active[(kind, episodeId)] = request;
    return request;
  }

  UnifiedDetailOperation? beginReadingReset() {
    if (_closed || isResettingReading) return null;
    // Claim first, then drain accepted chapter writes. No later read mutation
    // may race the work-wide reset, including writes whose adapter failed.
    final predecessors = _active.values
        .where(
          (request) => request.kind == UnifiedDetailOperationKind.readingState,
        )
        .map((request) => request._settled.future)
        .toList(growable: false);
    final request = UnifiedDetailOperation._(
      UnifiedDetailOperationKind.readingReset,
      null,
      Future.wait(predecessors).then((_) {}),
    );
    _active[(request.kind, null)] = request;
    return request;
  }

  bool owns(UnifiedDetailOperation request) =>
      !_closed &&
      identical(_active[(request.kind, request.episodeId)], request);

  void finish(UnifiedDetailOperation request) {
    if (identical(_active[(request.kind, request.episodeId)], request)) {
      _active.remove((request.kind, request.episodeId));
    }
    request._finish();
  }

  void close() {
    _closed = true;
    final requests = _active.values.toList(growable: false);
    _active.clear();
    for (final request in requests) {
      request._finish();
    }
  }
}
