import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Shared admission for data-only renderer preparation. Result types isolate
/// identities; scopes retire queued consumers without cancelling another owner.
/// Completed values belong to callers, never a scheduler cache.
final class ForumPreparationScheduler extends ChangeNotifier {
  ForumPreparationScheduler({
    this.maxConcurrent = 1,
    this.maxQueued = 16,
    this.maxQueuedCodeUnits = 512 * 1024,
  }) : assert(maxConcurrent > 0),
       assert(maxQueued >= 0),
       assert(maxQueuedCodeUnits >= 0);

  static final shared = ForumPreparationScheduler();
  final int maxConcurrent;
  final int maxQueued;
  final int maxQueuedCodeUnits;
  final _entries = <(Type, Object), _ScheduledEntry>{};
  final _queue = Queue<_ScheduledEntry>();
  int _active = 0;
  int _queuedCodeUnits = 0;
  bool _closed = false;
  bool _notificationScheduled = false;
  int get activeCount => _active;
  int get queuedCount => _queue.length;
  int get queuedCodeUnits => _queuedCodeUnits;

  ForumPreparationScope createScope() {
    if (_closed) throw StateError('Preparation scheduler is closed');
    return ForumPreparationScope._(this);
  }

  ForumPreparationLease<T>? _acquire<T extends Object>({
    required Object owner,
    required Object identity,
    required int codeUnits,
    required Future<T> Function() work,
  }) {
    if (_closed) throw StateError('Preparation scheduler is closed');
    if (codeUnits < 0) throw ArgumentError.value(codeUnits, 'codeUnits');
    final key = (T, identity);
    final existing = _entries[key];
    if (existing != null) {
      existing.addOwner(owner);
      return ForumPreparationLease<T>._(
        this,
        existing as _TypedEntry<T>,
        owner,
      );
    }
    final canStart = _active < maxConcurrent;
    if (!canStart &&
        (_queue.length >= maxQueued ||
            _queuedCodeUnits + codeUnits > maxQueuedCodeUnits)) {
      return null;
    }
    final entry = _TypedEntry<T>(key, codeUnits, work)..addOwner(owner);
    _entries[key] = entry;
    if (canStart) {
      _start(entry);
    } else {
      _queue.add(entry);
      _queuedCodeUnits += codeUnits;
    }
    return ForumPreparationLease<T>._(this, entry, owner);
  }

  void _start(_ScheduledEntry entry) {
    entry.started = true;
    _active++;
    entry.run().whenComplete(() {
      _active--;
      if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
      while (!_closed && _active < maxConcurrent && _queue.isNotEmpty) {
        final next = _queue.removeFirst();
        _queuedCodeUnits -= next.codeUnits;
        _start(next);
      }
      _capacityChanged();
    });
  }

  void _release(_ScheduledEntry entry, Object owner) {
    final count = entry.owners[owner];
    if (count == null) return;
    if (count == 1) {
      entry.owners.remove(owner);
    } else {
      entry.owners[owner] = count - 1;
    }
    entry.consumers--;
    _retireQueuedIfUnused(entry);
  }

  void _releaseOwner(Object owner) {
    for (final entry in _entries.values.toList()) {
      entry.consumers -= entry.owners.remove(owner) ?? 0;
      _retireQueuedIfUnused(entry);
    }
  }

  void _retireQueuedIfUnused(_ScheduledEntry entry) {
    if (entry.consumers != 0 || entry.started) return;
    if (_queue.remove(entry)) {
      _queuedCodeUnits -= entry.codeUnits;
      _entries.remove(entry.key);
      entry.cancelQueued();
      _capacityChanged();
    }
  }

  void _capacityChanged() {
    if (_closed || _notificationScheduled) return;
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (!_closed) notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final entry in _queue) {
      _entries.remove(entry.key);
      entry.cancelQueued();
    }
    _queue.clear();
    _queuedCodeUnits = 0;
    // In-flight workers keep their real slot until completion, including close.
    super.dispose();
  }
}

final class ForumPreparationScope {
  ForumPreparationScope._(this._scheduler);
  final ForumPreparationScheduler _scheduler;
  final _owner = Object();
  bool _closed = false;

  /// Work callbacks capture data inputs and worker ports, never a UI owner.
  ForumPreparationLease<T>? tryAcquire<T extends Object>({
    required Object identity,
    required int codeUnits,
    required Future<T> Function() work,
  }) {
    if (_closed) throw StateError('Preparation scope is closed');
    return _scheduler._acquire<T>(
      owner: _owner,
      identity: identity,
      codeUnits: codeUnits,
      work: work,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _scheduler._releaseOwner(_owner);
  }
}

abstract interface class ForumPreparationWorkLease<T extends Object> {
  Future<T?> get future;
  void release();
}

final class ForumPreparationLease<T extends Object>
    implements ForumPreparationWorkLease<T> {
  ForumPreparationLease._(this._scheduler, this._entry, this._owner);
  final ForumPreparationScheduler _scheduler;
  final _TypedEntry<T> _entry;
  final Object _owner;
  bool _released = false;
  @override
  Future<T?> get future => _entry.completer.future;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _scheduler._release(_entry, _owner);
  }
}

abstract class _ScheduledEntry {
  _ScheduledEntry(this.key, this.codeUnits);
  final (Type, Object) key;
  final int codeUnits;
  final owners = <Object, int>{};
  int consumers = 0;
  bool started = false;
  void addOwner(Object owner) {
    owners[owner] = (owners[owner] ?? 0) + 1;
    consumers++;
  }

  Future<void> run();
  void cancelQueued();
}

final class _TypedEntry<T extends Object> extends _ScheduledEntry {
  _TypedEntry(super.key, super.codeUnits, this.work);
  final Future<T> Function() work;
  final completer = Completer<T?>();
  @override
  Future<void> run() => Future<T>.sync(work).then<void>(
    completer.complete,
    onError: (Object error, StackTrace stack) =>
        completer.completeError(error, stack),
  );
  @override
  void cancelQueued() => completer.complete(null);
}
