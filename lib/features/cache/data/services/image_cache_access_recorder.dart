import 'dart:async';

import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';

/// Records LRU access without making a cache hit wait for SQLite writes.
abstract interface class ImageCacheAccessRecorder {
  void record(String cacheKey, DateTime accessedAt);

  Future<void> flush();

  Future<void> dispose();
}

final class BufferedImageCacheAccessRecorder
    implements ImageCacheAccessRecorder {
  BufferedImageCacheAccessRecorder({
    required ImageCacheRepository repository,
    this.flushInterval = const Duration(seconds: 2),
    this.maxPendingKeys = 64,
  }) : _repository = repository;

  final ImageCacheRepository _repository;
  final Duration flushInterval;
  final int maxPendingKeys;
  final Map<String, DateTime> _pending = <String, DateTime>{};
  Timer? _timer;
  Future<void>? _activeFlush;
  bool _disposed = false;

  @override
  void record(String cacheKey, DateTime accessedAt) {
    if (_disposed) {
      return;
    }
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) {
      return;
    }
    final previous = _pending[normalized];
    if (previous == null || accessedAt.isAfter(previous)) {
      _pending[normalized] = accessedAt;
    }
    if (_pending.length >= maxPendingKeys) {
      unawaited(flush());
      return;
    }
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  @override
  Future<void> flush() {
    final active = _activeFlush;
    if (active != null) {
      return active.then((_) {
        if (_pending.isNotEmpty) {
          return flush();
        }
      });
    }
    if (_pending.isEmpty) {
      return Future<void>.value();
    }
    _timer?.cancel();
    _timer = null;
    final batch = Map<String, DateTime>.of(_pending);
    _pending.clear();
    late final Future<void> task;
    task = _write(batch)
        .catchError((Object _) {
          if (!_disposed) {
            for (final MapEntry(key: key, value: accessedAt) in batch.entries) {
              final pendingAt = _pending[key];
              if (pendingAt == null || accessedAt.isAfter(pendingAt)) {
                _pending[key] = accessedAt;
              }
            }
            _timer ??= Timer(flushInterval, () {
              _timer = null;
              unawaited(flush());
            });
          }
        })
        .whenComplete(() {
          if (identical(_activeFlush, task)) {
            _activeFlush = null;
          }
        });
    _activeFlush = task;
    return task;
  }

  Future<void> _write(Map<String, DateTime> accesses) async {
    final repository = _repository;
    if (repository is ImageCacheBatchAccessRepository) {
      await (repository as ImageCacheBatchAccessRepository).touchMany(accesses);
      return;
    }
    for (final MapEntry(key: cacheKey, value: accessedAt) in accesses.entries) {
      await repository.touch(cacheKey, accessedAt);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await flush();
  }
}
