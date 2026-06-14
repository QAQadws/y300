import 'dart:async';

enum FavoriteSyncExecutionMode {
  bootstrapInitial,
  automaticResume,
  manualRecentAdd,
}

enum FavoriteFirstSyncRequestKind {
  favoriteListPage,
  favoriteThreadDetail,
  comicThreadDetail,
  comicCatalogHtml,
  comicForumSearch,
  novelSeedDetail,
  novelEpisodePage,
}

class FavoriteSyncExecutionContext {
  const FavoriteSyncExecutionContext({
    required this.mode,
    this.governor,
  });

  const FavoriteSyncExecutionContext.bootstrapInitial({
    required FavoriteFirstSyncRequestGovernor governor,
  }) : this(
         mode: FavoriteSyncExecutionMode.bootstrapInitial,
         governor: governor,
       );

  const FavoriteSyncExecutionContext.automaticResume()
      : this(mode: FavoriteSyncExecutionMode.automaticResume);

  const FavoriteSyncExecutionContext.manualRecentAdd()
      : this(mode: FavoriteSyncExecutionMode.manualRecentAdd);

  final FavoriteSyncExecutionMode mode;
  final FavoriteFirstSyncRequestGovernor? governor;

  bool get isBootstrapInitial =>
      mode == FavoriteSyncExecutionMode.bootstrapInitial;
}

abstract interface class FavoriteFirstSyncRequestGovernor {
  Future<T> run<T>({
    required FavoriteFirstSyncRequestKind kind,
    required Future<T> Function() action,
  });
}

class DefaultFavoriteFirstSyncRequestGovernor
    implements FavoriteFirstSyncRequestGovernor {
  DefaultFavoriteFirstSyncRequestGovernor({
    this.cooldown = const Duration(seconds: 1),
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
    required FavoriteFirstSyncRequestKind kind,
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
