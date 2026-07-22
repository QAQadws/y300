import 'dart:async';

import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';

final class CacheBudgetScheduler {
  CacheBudgetScheduler({
    required CacheMutationSource source,
    required Future<void> Function() enforce,
    this.debounce = const Duration(seconds: 2),
  }) : _source = source,
       _enforce = enforce;

  final CacheMutationSource _source;
  final Future<void> Function() _enforce;
  final Duration debounce;
  StreamSubscription<Object?>? _subscription;
  Timer? _timer;
  Future<void>? _active;
  bool _rerunRequested = false;
  bool _disposed = false;

  Future<void> start() {
    if (_disposed) {
      return Future<void>.value();
    }
    _subscription ??= _source.mutations.listen((_) => _schedule());
    return _run();
  }

  void _schedule() {
    if (_disposed) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_run());
    });
  }

  Future<void> _run() {
    final active = _active;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    late final Future<void> operation;
    operation = _enforce().catchError((Object _) {}).whenComplete(() {
      if (!identical(_active, operation)) {
        return;
      }
      _active = null;
      if (_rerunRequested && !_disposed) {
        _rerunRequested = false;
        unawaited(_run());
      }
    });
    _active = operation;
    return operation;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
