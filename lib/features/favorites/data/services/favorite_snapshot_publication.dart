/// Coalesces waiting foreground publications. Each action reads the latest
/// committed shelf, so several completed targets need only one snapshot write.
class FavoriteSnapshotPublication {
  final Map<Object?, Future<void>> _pending = {};

  Future<void> request(Object? owner, Future<void> Function() publish) {
    final existing = _pending[owner];
    if (existing != null) return existing;
    late final Future<void> future;
    future = publish().whenComplete(() {
      if (identical(_pending[owner], future)) _pending.remove(owner);
    });
    _pending[owner] = future;
    return future;
  }
}
