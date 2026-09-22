import 'dart:async';

/// Owns in-flight navigation, including dialogs and the pushed route lifetime.
/// Requests are shared only within this owner; completed locations are not cached.
final class ThreadPostNavigationSession {
  int _generation = 0;
  Object? _key;
  Future<void>? _pending;
  bool _disposed = false;

  Future<void> run({
    required Object key,
    required bool Function() isCurrent,
    required Future<void> Function(bool Function() isCurrent) action,
  }) {
    if (_disposed || !isCurrent()) return Future<void>.value();
    if (_key == key && _pending != null) return _pending!;
    final generation = ++_generation;
    final completion = Completer<void>();
    _key = key;
    _pending = completion.future;
    Future<void>.microtask(() async {
      bool current() => !_disposed && generation == _generation && isCurrent();
      try {
        if (current()) await action(current);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        if (generation == _generation) {
          _pending = null;
          _key = null;
        }
      }
    });
    return completion.future;
  }

  void invalidate() {
    _generation++;
    _pending = null;
    _key = null;
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}
