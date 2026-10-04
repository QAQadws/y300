import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

typedef NovelReaderPaginationIdleScheduler = Future<void> Function();

/// Page-level scheduling for a live, sequential pagination run.
///
/// Call the lease after publishing sealed pages. Target work proceeds eagerly;
/// background work yields to Flutter idle tasks, with a bounded starvation wait.
final class NovelReaderPaginationDemand extends ChangeNotifier {
  NovelReaderPaginationDemand({
    this.lookAhead = 2,
    Duration idleBudget = const Duration(milliseconds: 100),
    NovelReaderPaginationIdleScheduler? idleScheduler,
  }) : assert(lookAhead >= 0),
       assert(idleBudget > Duration.zero),
       assert(idleBudget <= const Duration(milliseconds: 100)),
       _idleBudget = idleBudget,
       _idleScheduler = idleScheduler ?? _scheduleIdle;

  final int lookAhead;
  final Duration _idleBudget;
  final NovelReaderPaginationIdleScheduler _idleScheduler;
  bool _targetPending = true;
  int _pageIndex = 0;
  bool _requireComplete = false;
  bool _disposed = false;
  NovelReaderPaginationDemandLease? _currentLease;

  bool get isDeferring => _currentLease?._wait != null;

  void update({
    required bool targetPending,
    required int pageIndex,
    bool requireComplete = false,
  }) {
    assert(pageIndex >= 0);
    if (_disposed) {
      return;
    }
    _targetPending = targetPending;
    _pageIndex = pageIndex;
    _requireComplete = requireComplete;
    _currentLease?._demandChanged();
  }

  NovelReaderPaginationDemandLease start(
    NovelReaderPaginationCancellationToken token,
  ) {
    if (_disposed) {
      throw StateError('Pagination demand has been disposed.');
    }
    token.throwIfCancelled();
    final wasDeferring = isDeferring;
    final previous = _currentLease;
    final lease = NovelReaderPaginationDemandLease._(this, token);
    _currentLease = lease;
    previous?.close();
    lease._removeCancelListener = token.onCancel(lease._releaseCurrentWait);
    if (wasDeferring) {
      notifyListeners();
    }
    return lease;
  }

  bool _needsForegroundWork(int pageCount) =>
      _targetPending ||
      _requireComplete ||
      pageCount < _pageIndex + 1 + lookAhead;

  void _deferralChanged(NovelReaderPaginationDemandLease lease) {
    if (!_disposed && identical(_currentLease, lease)) {
      notifyListeners();
    }
  }

  static Future<void> _scheduleIdle() => SchedulerBinding.instance
      .scheduleTask<void>(() {}, Priority.idle, debugLabel: 'novel pagination');

  @override
  void dispose() {
    _disposed = true;
    final lease = _currentLease;
    _currentLease = null;
    lease?.close();
    super.dispose();
  }
}

final class NovelReaderPaginationDemandLease {
  NovelReaderPaginationDemandLease._(this._demand, this._token);

  final NovelReaderPaginationDemand _demand;
  final NovelReaderPaginationCancellationToken _token;
  void Function()? _removeCancelListener;
  _PublicationWait? _wait;
  bool _closed = false;

  Future<void> afterPublication(
    int pageCount, {
    bool isComplete = false,
  }) async {
    _token.throwIfCancelled();
    if (_closed ||
        !identical(_demand._currentLease, this) ||
        isComplete ||
        _demand._needsForegroundWork(pageCount)) {
      _releaseCurrentWait();
      return;
    }

    var wait = _wait;
    if (wait == null) {
      wait = _PublicationWait(pageCount);
      _wait = wait;
      final scheduledWait = wait;
      wait.timer = Timer(_demand._idleBudget, () => _release(scheduledWait));
      _demand._deferralChanged(this);
      // A listener may synchronously promote demand or retire this lease.
      if (identical(_wait, wait)) {
        try {
          unawaited(
            _demand._idleScheduler().then<void>(
              (_) => _release(scheduledWait),
              onError: (Object error, StackTrace stack) =>
                  _release(scheduledWait, error: error, stack: stack),
            ),
          );
        } catch (error, stack) {
          _release(scheduledWait, error: error, stack: stack);
        }
      }
    }

    try {
      await wait.completion.future;
      _token.throwIfCancelled();
    } finally {
      _release(wait);
    }
  }

  void _demandChanged() {
    final wait = _wait;
    if (wait != null && _demand._needsForegroundWork(wait.pageCount)) {
      _release(wait);
    }
  }

  void _releaseCurrentWait() {
    final wait = _wait;
    if (wait != null) {
      _release(wait);
    }
  }

  void _release(_PublicationWait wait, {Object? error, StackTrace? stack}) {
    if (!identical(_wait, wait)) {
      return;
    }
    _wait = null;
    wait.timer?.cancel();
    if (error == null) {
      wait.completion.complete();
    } else {
      wait.completion.completeError(error, stack);
    }
    _demand._deferralChanged(this);
  }

  /// Releases scheduling resources; the owner still cancels obsolete work.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _removeCancelListener?.call();
    _removeCancelListener = null;
    _releaseCurrentWait();
  }
}

final class _PublicationWait {
  _PublicationWait(this.pageCount);

  final int pageCount;
  final Completer<void> completion = Completer<void>();
  Timer? timer;
}
