import 'dart:async';

import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';

// Adjust this single constant when tuning favorite sync request pacing.
// Applies to ALL favorite sync modes (first / automatic-resume / manual
// recent-add) — every governed parse request waits this long after the
// previous one completes, to avoid tripping the site's temporary IP ban.
const Duration favoriteSyncGovernorCooldown = Duration(milliseconds: 700);

@Deprecated('Renamed to favoriteSyncGovernorCooldown (now covers all sync modes).')
const Duration favoriteFirstSyncGovernorCooldown = favoriteSyncGovernorCooldown;

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
  // 注意：漫画论坛搜索由 ForumSearchScheduler（~10.5s 节奏）独立管控，
  // 不再走 favorite first-sync governor 的槽。这里删掉旧的 comicForumSearch
  // 枚举项以避免误用。
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

  // Subsequent syncs are governed too: the same request pacing must apply so a
  // resume / manual add can't burst-fire parse requests and trip an IP ban.
  const FavoriteSyncExecutionContext.automaticResume({
    FavoriteFirstSyncRequestGovernor? governor,
  }) : this(
         mode: FavoriteSyncExecutionMode.automaticResume,
         governor: governor,
       );

  const FavoriteSyncExecutionContext.manualRecentAdd({
    FavoriteFirstSyncRequestGovernor? governor,
  }) : this(
         mode: FavoriteSyncExecutionMode.manualRecentAdd,
         governor: governor,
       );

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
    this.cooldown = favoriteSyncGovernorCooldown,
    DateTime Function()? nowProvider,
    Future<void> Function(Duration duration)? delay,
    SyncDiagnosticRecorder? diagnosticRecorder,
  }) : _nowProvider = nowProvider ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _diagnosticRecorder =
           diagnosticRecorder ?? const NoopSyncDiagnosticRecorder();

  final Duration cooldown;
  final DateTime Function() _nowProvider;
  final Future<void> Function(Duration duration) _delay;
  final SyncDiagnosticRecorder _diagnosticRecorder;

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
      final startedAt = _nowProvider();
      _diagnosticRecorder.record(
        scope: 'favorite_first_sync_governor',
        event: 'request_scheduled',
        fields: <String, Object?>{
          'kind': kind.name,
          'cooldownMs': cooldown.inMilliseconds,
          'waitMs': wait.inMilliseconds,
        },
      );
      if (wait > Duration.zero) {
        await _delay(wait);
      }
      try {
        final result = await action();
        _diagnosticRecorder.record(
          scope: 'favorite_first_sync_governor',
          event: 'request_succeeded',
          fields: <String, Object?>{
            'kind': kind.name,
            'waitMs': wait.inMilliseconds,
            'elapsedMs':
                _nowProvider().difference(startedAt).inMilliseconds,
          },
        );
        completer.complete(result);
      } catch (error, stackTrace) {
        _diagnosticRecorder.record(
          scope: 'favorite_first_sync_governor',
          event: 'request_failed',
          fields: <String, Object?>{
            'kind': kind.name,
            'waitMs': wait.inMilliseconds,
            'elapsedMs':
                _nowProvider().difference(startedAt).inMilliseconds,
            'error': '$error',
          },
        );
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
