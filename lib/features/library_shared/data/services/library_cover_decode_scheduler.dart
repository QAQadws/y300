import 'dart:async';
import 'dart:ui' as ui;

/// Bounds codec creation AND first-frame decoding, independently of downloads.
/// ImageCache owns request deduplication. Codecs are stateful and must never
/// be shared by independently owned ImageStreamCompleters.
class LibraryCoverDecodeScheduler {
  LibraryCoverDecodeScheduler({required int maxConcurrent})
    : _maxConcurrent = maxConcurrent.clamp(1, 3).toInt();

  final int _maxConcurrent;
  final List<_QueuedDecode> _pending = <_QueuedDecode>[];
  int _running = 0;
  Completer<void>? _idle;

  int get activeCount => _running;
  int get pendingCount => _pending.length;

  Future<void> whenIdle() {
    if (_running == 0 && _pending.isEmpty) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  Future<ui.Codec> schedule({
    required Object key,
    required Future<ui.Codec> Function() action,
  }) {
    final task = _QueuedDecode(key: key, action: action);
    _pending.add(task);
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
      _running -= 1;
      _drain();
      if (_running == 0 && _pending.isEmpty) {
        _idle?.complete();
        _idle = null;
      }
    }
  }
}

class _QueuedDecode {
  _QueuedDecode({required this.key, required this.action});

  final Object key;
  final Future<ui.Codec> Function() action;
  final Completer<ui.Codec> completer = Completer<ui.Codec>();
}
