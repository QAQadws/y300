import 'package:flutter/foundation.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';

enum FavoriteSyncProgressPhase {
  idle,
  queued,
  fetchingList,
  savingList,
  loadingDetails,
  finishing,
  completed,
  failed,
}

class FavoriteSyncProgress {
  const FavoriteSyncProgress({
    required this.phase,
    this.subject,
    this.current = 0,
    this.total,
    this.hasQueueSummary = false,
    this.foregroundQueued = 0,
    this.automaticRemaining = 0,
    this.failedCount = 0,
    this.needsReconciliation = false,
  });

  final FavoriteSyncProgressPhase phase;

  /// Raw server title, localized only by the presentation layer.
  final String? subject;
  final int current;
  final int? total;
  final bool hasQueueSummary;
  final int foregroundQueued, automaticRemaining, failedCount;
  final bool needsReconciliation;

  bool get isActive => switch (phase) {
    FavoriteSyncProgressPhase.idle ||
    FavoriteSyncProgressPhase.completed ||
    FavoriteSyncProgressPhase.failed => false,
    _ => true,
  };

  double? get fraction => total == null || total! <= 0
      ? null
      : (current / total!).clamp(0.0, 1.0).toDouble();

  static const idle = FavoriteSyncProgress(
    phase: FavoriteSyncProgressPhase.idle,
  );
}

/// Keeps the executing detail separate from the suspended directory phase.
/// Durable queue snapshots include jobs beyond the coordinator's claim window.
class FavoriteSyncProgressTracker {
  final notifier = ValueNotifier<FavoriteSyncProgress>(
    FavoriteSyncProgress.idle,
  );
  FavoriteSyncProgress _round = FavoriteSyncProgress.idle;
  FavoriteParseQueueStatus _queue = const FavoriteParseQueueStatus();
  final Map<String, int> _foreground = {};
  final Set<String> _failed = {};
  int _rounds = 0, _automatic = 0;
  String? _activeTid, _subject;
  bool _roundFailed = false, _reconcile = false, _started = false;

  void reset() {
    _round = FavoriteSyncProgress.idle;
    _queue = const FavoriteParseQueueStatus();
    _foreground.clear();
    _failed.clear();
    _rounds = _automatic = 0;
    _activeTid = _subject = null;
    _roundFailed = _reconcile = _started = false;
    notifier.value = FavoriteSyncProgress.idle;
  }

  void beginRound() {
    _started = true;
    _roundFailed = _reconcile = false;
    _rounds++;
    publish();
  }

  void endRound() {
    if (_rounds > 0) _rounds--;
    if (_rounds == 0) _automatic = 0;
    publish();
  }

  void round(FavoriteSyncProgress value) {
    _round = value;
    if (value.phase == FavoriteSyncProgressPhase.failed) _roundFailed = true;
    if (value.phase == FavoriteSyncProgressPhase.completed) {
      _roundFailed = false;
    }
    publish();
  }

  void reconciliation(bool needed) {
    _reconcile = needed;
    publish();
  }

  void automaticRemaining(int count) {
    _automatic = count < 0 ? 0 : count;
    publish();
  }

  void queue(FavoriteParseQueueStatus value) {
    _queue = value;
    _started = true;
    publish();
  }

  void beginForeground(String tid) {
    _started = true;
    _foreground.update(tid, (count) => count + 1, ifAbsent: () => 1);
    publish();
  }

  void endForeground(String tid) {
    final count = (_foreground[tid] ?? 1) - 1;
    if (count <= 0) {
      _foreground.remove(tid);
    } else {
      _foreground[tid] = count;
    }
    publish();
  }

  void detail(String tid, String title) {
    _activeTid = tid;
    _subject = title;
    publish();
  }

  void detailSettled(String tid, {bool? succeeded}) {
    if (succeeded == true) _failed.remove(tid);
    if (succeeded == false) _failed.add(tid);
    if (_activeTid == tid) _activeTid = _subject = null;
    publish();
  }

  void forgetDetails(Set<String> tids) {
    if (tids.isEmpty) return;
    _failed.removeAll(tids);
    _queue = FavoriteParseQueueStatus(
      pendingTids: _queue.pendingTids,
      failedTids: _queue.failedTids.difference(tids),
    );
    publish();
  }

  void publish() {
    final pending = {..._queue.pendingTids, ..._foreground.keys};
    final waiting = pending.difference({?_activeTid}).length;
    final failures = {..._failed, ..._queue.failedTids}.length;
    final active = _rounds > 0 || pending.isNotEmpty || _activeTid != null;
    final FavoriteSyncProgressPhase phase;
    if (active) {
      phase = _activeTid != null
          ? FavoriteSyncProgressPhase.loadingDetails
          : _rounds > 0 && _round.isActive
          ? _round.phase
          : FavoriteSyncProgressPhase.queued;
    } else if (failures > 0 || _roundFailed || _reconcile) {
      phase = FavoriteSyncProgressPhase.failed;
    } else {
      phase = _started
          ? FavoriteSyncProgressPhase.completed
          : FavoriteSyncProgressPhase.idle;
    }
    notifier.value = FavoriteSyncProgress(
      phase: phase,
      subject: _activeTid == null ? _round.subject : _subject,
      current: _activeTid == null ? _round.current : 0,
      total: _activeTid == null ? _round.total : null,
      hasQueueSummary: true,
      foregroundQueued: waiting,
      automaticRemaining: _automatic,
      failedCount: failures,
      needsReconciliation: _reconcile || _roundFailed,
    );
  }
}
