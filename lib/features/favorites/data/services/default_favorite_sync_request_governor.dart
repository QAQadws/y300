import 'dart:async';

import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';

class DefaultFavoriteSyncRequestGovernor
    implements FavoriteSyncRequestGovernor {
  DefaultFavoriteSyncRequestGovernor({
    this.cooldown = favoriteSyncGovernorCooldown,
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
  Future<T> run<T>({
    required FavoriteSyncRequestKind kind,
    required Future<T> Function() action,
  }) {
    final completer = Completer<T>();
    final previousTail = _tail;
    late final Future<void> scheduled;
    scheduled = previousTail.then((_) async {
      final wait = _remainingCooldown();
      if (wait > Duration.zero) {
        await _delay(wait);
      }
      try {
        final result = await action();
        completer.complete(result);
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
