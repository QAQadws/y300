import 'dart:async';

/// Coordinates publishing an App image record with lower-level orphan cleanup.
/// Only active work is retained; completed keys never accumulate here.
final class ImageCacheFileAccess {
  final _readers = <String, int>{};
  final _deletions = <String, Completer<void>>{};
  Object _resolutionEpoch = Object();
  int _mutations = 0;

  /// Conservative invalidation avoids retaining a per-file generation map.
  Object? get reusableEpoch => _mutations == 0 ? _resolutionEpoch : null;

  void invalidateResolutions() => _resolutionEpoch = Object();

  Future<({T value, Object epoch})> mutate<T>(
    Future<T> Function() action,
  ) async {
    _mutations++;
    invalidateResolutions();
    late T value;
    try {
      value = await action();
    } finally {
      _mutations--;
      invalidateResolutions();
    }
    // Pair the completed result and epoch before yielding to its consumer.
    // A concurrent mutation or a read begun during mutation cannot authorize reuse.
    return (value: value, epoch: _resolutionEpoch);
  }

  Future<T> protect<T>(String key, Future<T> Function() action) async {
    while (true) {
      final pending = _deletions[key];
      if (pending == null) break;
      await pending.future;
    }
    _readers.update(key, (count) => count + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      final remaining = _readers[key]! - 1;
      if (remaining == 0) {
        _readers.remove(key);
      } else {
        _readers[key] = remaining;
      }
    }
  }

  Future<bool> deleteIfIdle(String key, Future<void> Function() action) async {
    if (_readers.containsKey(key) || _deletions.containsKey(key)) return false;
    final completion = Completer<void>();
    _deletions[key] = completion;
    try {
      await mutate(action);
      return true;
    } finally {
      _deletions.remove(key);
      completion.complete();
    }
  }
}
