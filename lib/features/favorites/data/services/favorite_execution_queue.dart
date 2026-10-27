import 'dart:async';

enum FavoriteWorkPriority { foreground, automatic, maintenance }

/// One execution slot. Only stable units, never a whole sync awaiting its own
/// child tasks, occupy this queue.
class FavoriteExecutionQueue {
  final List<_Work> _pending = [];
  Completer<void>? _idle;
  bool _running = false;
  int _foregroundBurst = 0;

  Future<void> get settled => _idle?.future ?? Future<void>.value();

  Future<T> run<T>(
    Future<T> Function() action, {
    FavoriteWorkPriority priority = FavoriteWorkPriority.automatic,
    FavoriteWorkPriority Function()? currentPriority,
  }) {
    final result = Completer<T>();
    _idle ??= Completer<void>();
    _pending.add(
      _Work(currentPriority ?? () => priority, () async {
        try {
          result.complete(await action());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      }),
    );
    if (!_running) {
      _running = true;
      scheduleMicrotask(_drain);
    }
    return result.future;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      var index = _pending.indexWhere(
        (e) => e.priority() == FavoriteWorkPriority.foreground,
      );
      final automatic = _pending.indexWhere(
        (e) => e.priority() == FavoriteWorkPriority.automatic,
      );
      if (index < 0 || (_foregroundBurst >= 3 && automatic >= 0)) {
        index = automatic;
      }
      if (index < 0) index = 0;
      final task = _pending.removeAt(index);
      _foregroundBurst = task.priority() == FavoriteWorkPriority.foreground
          ? _foregroundBurst + 1
          : 0;
      await task.execute();
    }
    _running = false;
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }
}

class _Work {
  _Work(this.priority, this.execute);
  final FavoriteWorkPriority Function() priority;
  final Future<void> Function() execute;
}
