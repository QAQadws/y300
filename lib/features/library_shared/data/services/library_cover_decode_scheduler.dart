import 'dart:async';
import 'dart:ui' as ui;

/// Bounds cover codec creation independently from network fetch concurrency.
/// Requests with the same key share one queued or running decode.
class LibraryCoverDecodeScheduler {
  LibraryCoverDecodeScheduler({required int maxConcurrent})
    : _maxConcurrent = maxConcurrent.clamp(1, 3).toInt();

  final int _maxConcurrent;
  final List<_QueuedDecode> _pending = <_QueuedDecode>[];
  final Map<Object, _QueuedDecode> _byKey = <Object, _QueuedDecode>{};
  int _running = 0;

  Future<ui.Codec> schedule({
    required Object key,
    required Future<ui.Codec> Function() action,
  }) {
    final existing = _byKey[key];
    if (existing != null) {
      return existing.completer.future;
    }
    final task = _QueuedDecode(key: key, action: action);
    _pending.add(task);
    _byKey[key] = task;
    _drain();
    return task.completer.future;
  }

  void _drain() {
    while (_running < _maxConcurrent && _pending.isNotEmpty) {
      final task = _pending.removeAt(0);
      _running += 1;
      unawaited(_run(task));
    }
  }

  Future<void> _run(_QueuedDecode task) async {
    try {
      task.completer.complete(await task.action());
    } catch (error, stackTrace) {
      task.completer.completeError(error, stackTrace);
    } finally {
      _byKey.remove(task.key);
      _running -= 1;
      _drain();
    }
  }
}

class _QueuedDecode {
  _QueuedDecode({required this.key, required this.action});

  final Object key;
  final Future<ui.Codec> Function() action;
  final Completer<ui.Codec> completer = Completer<ui.Codec>();
}
