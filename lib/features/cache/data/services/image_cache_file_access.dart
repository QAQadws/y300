import 'dart:async';

/// Coordinates publishing an App image record with lower-level orphan cleanup.
/// Only active work is retained; completed keys never accumulate here.
final class ImageCacheFileAccess {
  final _readers = <String, int>{};
  final _deletions = <String, Completer<void>>{};

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
      await action();
      return true;
    } finally {
      _deletions.remove(key);
      completion.complete();
    }
  }
}
