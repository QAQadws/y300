import 'dart:async';

/// Owns in-flight navigation, including dialogs and the pushed route lifetime.
/// Requests are shared only within this owner; completed locations are not cached.
final class ThreadPostNavigationSession {
  int _generation = 0;
  Object? _key;
  Future<void>? _pending;
  bool Function()? _pendingIsCurrent;
  bool _disposed = false;

  Future<void> run({
    required Object key,
    required bool Function() isCurrent,
    required Future<void> Function(bool Function() isCurrent) action,
  }) {
    if (_disposed || !isCurrent()) return Future<void>.value();
    // A repeated target can belong to a new selection lease. Do not join an
    // old request whose source has already retired, even if its work is pending.
    if (_key == key && _pending != null && _pendingIsCurrent?.call() == true) {
      return _pending!;
    }
    final generation = ++_generation;
    final completion = Completer<void>();
    bool current() => !_disposed && generation == _generation && isCurrent();
    _key = key;
    _pending = completion.future;
    _pendingIsCurrent = current;
    Future<void>.microtask(() async {
      try {
        if (current()) await action(current);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        if (generation == _generation) {
          _pending = null;
          _pendingIsCurrent = null;
          _key = null;
        }
      }
    });
    return completion.future;
  }

  void invalidate() {
    _generation++;
    _pending = null;
    _pendingIsCurrent = null;
    _key = null;
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}
