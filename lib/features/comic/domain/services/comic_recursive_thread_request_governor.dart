import 'dart:async';

const Duration comicRecursiveThreadRequestCooldown = Duration(
  milliseconds: 700,
);

abstract interface class ComicRecursiveThreadRequestGovernor {
  Future<T> schedule<T>(Future<T> Function() request);
}

final class DefaultComicRecursiveThreadRequestGovernor
    implements ComicRecursiveThreadRequestGovernor {
  DefaultComicRecursiveThreadRequestGovernor({
    this.cooldown = comicRecursiveThreadRequestCooldown,
    DateTime Function()? nowProvider,
    Future<void> Function(Duration duration)? delay,
  }) : _nowProvider = nowProvider ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final Duration cooldown;
  final DateTime Function() _nowProvider;
  final Future<void> Function(Duration duration) _delay;

  Future<void> _tail = Future<void>.value();
  DateTime? _lastCompletedAt;

  @override
  Future<T> schedule<T>(Future<T> Function() request) {
    final completer = Completer<T>();
    final previousTail = _tail;
    final scheduled = previousTail.then((_) async {
      final wait = _remainingCooldown();
      if (wait > Duration.zero) {
        await _delay(wait);
      }
      try {
        completer.complete(await request());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _lastCompletedAt = _nowProvider();
      }
    });
    _tail = scheduled.catchError((_) {});
    return completer.future;
  }

  Duration _remainingCooldown() {
    final lastCompletedAt = _lastCompletedAt;
    if (lastCompletedAt == null) {
      return Duration.zero;
    }
    final elapsed = _nowProvider().difference(lastCompletedAt);
    if (elapsed >= cooldown) {
      return Duration.zero;
    }
    return cooldown - elapsed;
  }
}
