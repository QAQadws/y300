import 'package:flutter/foundation.dart';

import 'forum_preparation_scheduler.dart';

/// Internal lifecycle shared by mounted preparation consumers. Identity includes
/// the consumer's owner; scheduler single-flight identity may deliberately omit
/// that owner to share data-only work between sessions.
final class ForumPreparationConsumer<T extends Object> extends ChangeNotifier {
  ForumPreparationConsumer(this._capacity);
  final Listenable _capacity;
  Object? _identity;
  T? _document;
  ForumPreparationWorkLease<T>? _lease;
  ForumPreparationWorkLease<T>? Function()? _admit;
  Object? _error;
  StackTrace? _stack;
  int _generation = 0;
  bool _waiting = false;
  bool _closed = false;

  Object? get identity => _identity;
  bool get hasError => _error != null;

  T? resolve({
    required Object identity,
    required ForumPreparationWorkLease<T>? Function() admit,
    T Function()? prepareSynchronously,
  }) {
    if (_closed) throw StateError('Preparation consumer is closed');
    if (_identity != identity) {
      reset();
      _identity = identity;
      if (prepareSynchronously != null) {
        return _document = prepareSynchronously();
      }
      _admit = admit;
      _acquire();
    }
    if (_error != null) Error.throwWithStackTrace(_error!, _stack!);
    // Keep explicit synchronous retry after an earlier synchronous failure.
    if (_document == null && _admit == null && prepareSynchronously != null) {
      return _document = prepareSynchronously();
    }
    return _document;
  }

  void _acquire() {
    final admit = _admit;
    if (_closed || admit == null || _lease != null) return;
    final lease = admit();
    if (lease == null) {
      if (!_waiting) {
        _waiting = true;
        _capacity.addListener(_acquire);
      }
      return;
    }
    _stopWaiting();
    _lease = lease;
    final generation = _generation;
    lease.future.then(
      (document) {
        lease.release();
        if (!_isCurrent(generation, lease)) return;
        _lease = null;
        _admit = null;
        if (document == null) {
          _error = StateError('Preparation request was retired');
          _stack = StackTrace.current;
        } else {
          _document = document;
        }
        notifyListeners();
      },
      onError: (Object error, StackTrace stack) {
        lease.release();
        if (!_isCurrent(generation, lease)) return;
        _lease = null;
        _admit = null;
        _error = error;
        _stack = stack;
        notifyListeners();
      },
    );
  }

  bool _isCurrent(int generation, ForumPreparationWorkLease<T> lease) =>
      !_closed && _generation == generation && identical(_lease, lease);

  void _stopWaiting() {
    if (!_waiting) return;
    _waiting = false;
    _capacity.removeListener(_acquire);
  }

  void reset() {
    _generation++;
    _stopWaiting();
    _lease?.release();
    _lease = null;
    _admit = null;
    _identity = null;
    _document = null;
    _error = null;
    _stack = null;
  }

  @override
  void dispose() {
    if (_closed) return;
    reset();
    _closed = true;
    super.dispose();
  }
}
