import 'dart:async';

import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

enum NovelReaderPagedWaitFailure { targetPage, backgroundIdle }

/// Identity of one explicit missing-page turn, not reading-position evidence.
final class NovelReaderPendingPageRequest {
  NovelReaderPendingPageRequest._(this.pageIndex);

  final int pageIndex;
}

/// Waiting and demand state for one mounted horizontal reading surface.
///
/// The host resolves semantic restore targets and owns streams, prefix checks,
/// Flutter animation and confirmed position reports. This object can only pause
/// waiting; it cannot change reading mode, confirm progress or turn a chapter.
final class NovelReaderPagedWaitCoordinator {
  NovelReaderPagedWaitCoordinator({
    required NovelReaderPaginationPerformancePolicy policy,
    required void Function(NovelReaderPagedWaitFailure) onTimeout,
  }) : _policy = policy,
       _onTimeout = onTimeout;

  NovelReaderPaginationPerformancePolicy _policy;
  final void Function(NovelReaderPagedWaitFailure) _onTimeout;
  Timer? _targetTimer;
  Timer? _backgroundTimer;
  Object? _targetDeadline;
  Object? _backgroundDeadline;
  bool _closed = false;
  bool _paused = false;
  bool _planActive = false;
  bool _planCompleted = false;
  bool _hasReadablePage = false;
  bool _targetReady = false;
  bool _restoreTargetPending = true;
  bool _isDeferring = false;
  int _availablePageCount = 0;
  int _attemptPublishedPageCount = 0;
  int _demandPageIndex = 0;
  NovelReaderPendingPageRequest? _pendingForwardRequest;

  bool get hasReadablePage => _hasReadablePage;
  bool get targetReady => _targetReady;
  bool get restoreTargetPending => _restoreTargetPending;
  bool get planCompleted => _planCompleted;
  int get demandPageIndex => _demandPageIndex;
  NovelReaderPendingPageRequest? get pendingForwardRequest =>
      _pendingForwardRequest;
  int? get pendingForwardPage => _pendingForwardRequest?.pageIndex;
  bool get forwardTargetPending =>
      pendingForwardPage != null && pendingForwardPage! >= _availablePageCount;
  bool get targetPending => _restoreTargetPending || forwardTargetPending;

  void updatePolicy(NovelReaderPaginationPerformancePolicy policy) {
    if (_closed) return;
    cancelTimers();
    _policy = policy;
  }

  void startTargetWait() {
    _cancelTargetTimer();
    if (_closed || _paused || !_policy.enforceBudgets) return;
    final deadline = _targetDeadline = Object();
    _targetTimer = Timer(_policy.targetPageWait, () {
      if (!_closed && identical(_targetDeadline, deadline) && !_targetReady) {
        _timeout(NovelReaderPagedWaitFailure.targetPage);
      }
    });
  }

  void beginNavigation() {
    if (_closed) return;
    _pendingForwardRequest = null;
    _restoreTargetPending = true;
    _targetReady = false;
    cancelTimers();
  }

  void startPlan() {
    if (_closed) return;
    _planActive = true;
    _planCompleted = false;
    _attemptPublishedPageCount = 0;
  }

  /// Replay progress counts even before it covers the retained readable prefix.
  /// Metric-only events and repeated page counts never renew the idle deadline.
  void recordPublication(int pageCount, {required bool isComplete}) {
    if (_closed ||
        _paused ||
        isComplete ||
        pageCount <= _attemptPublishedPageCount) {
      return;
    }
    _attemptPublishedPageCount = pageCount;
    _cancelBackgroundTimer();
    ensureBackgroundWait();
  }

  /// Called only after the host has validated layout and retained-page prefix.
  void acceptProgress(int pageCount, {required bool isComplete}) {
    if (_closed || _paused) return;
    _availablePageCount = pageCount;
    _planCompleted = isComplete;
    if (isComplete) cancelTimers();
  }

  void resolveRestoreTarget({
    required bool pending,
    required int? resolvedPage,
    required int pageCount,
    required bool isComplete,
  }) {
    if (_closed) return;
    if ((!_hasReadablePage || _restoreTargetPending) && resolvedPage != null) {
      _demandPageIndex = resolvedPage;
    }
    _restoreTargetPending = pending;
    _availablePageCount = pageCount;
    if (isComplete &&
        pendingForwardPage != null &&
        pendingForwardPage! >= pageCount) {
      // Finishing without the requested page never grants a chapter turn.
      _pendingForwardRequest = null;
    }
  }

  void markTargetReadable() {
    if (_closed) return;
    _hasReadablePage = true;
    _targetReady = true;
    _cancelTargetTimer();
  }

  void markPlanComplete() {
    if (_closed) return;
    _planCompleted = true;
    cancelTimers();
  }

  void setVisiblePage(int pageIndex) {
    if (!_closed) _demandPageIndex = pageIndex;
  }

  bool requestForwardPage(int target) {
    if (_closed ||
        _paused ||
        _pendingForwardRequest != null ||
        !_hasReadablePage ||
        target < 0 ||
        (_planCompleted && target >= _availablePageCount)) {
      return false;
    }
    _pendingForwardRequest = NovelReaderPendingPageRequest._(target);
    _targetReady = false;
    _cancelBackgroundTimer();
    startTargetWait();
    return true;
  }

  bool consumeForwardPage(
    NovelReaderPendingPageRequest request, {
    int? visiblePageIndex,
  }) {
    if (_closed ||
        _paused ||
        !identical(_pendingForwardRequest, request) ||
        request.pageIndex >= _availablePageCount) {
      return false;
    }
    cancelForwardPage(visiblePageIndex: visiblePageIndex);
    return true;
  }

  bool cancelForwardPage({int? visiblePageIndex}) {
    if (_closed || _pendingForwardRequest == null) return false;
    _pendingForwardRequest = null;
    _demandPageIndex = visiblePageIndex ?? _demandPageIndex;
    _targetReady = !_restoreTargetPending;
    if (_targetReady) _cancelTargetTimer();
    return true;
  }

  void setDeferring(bool value) {
    if (_closed) return;
    _isDeferring = value;
    if (value) {
      _cancelBackgroundTimer();
    } else {
      ensureBackgroundWait();
    }
  }

  void ensureBackgroundWait() {
    if (_closed ||
        _paused ||
        !_targetReady ||
        _planCompleted ||
        !_planActive ||
        _isDeferring ||
        _backgroundTimer != null ||
        !_policy.enforceBudgets) {
      return;
    }
    final deadline = _backgroundDeadline = Object();
    _backgroundTimer = Timer(_policy.backgroundIdle, () {
      if (!_closed &&
          identical(_backgroundDeadline, deadline) &&
          !_planCompleted) {
        _timeout(NovelReaderPagedWaitFailure.backgroundIdle);
      }
    });
  }

  void _timeout(NovelReaderPagedWaitFailure failure) {
    pause();
    _onTimeout(failure);
  }

  void pause() {
    if (_closed) return;
    _paused = true;
    _planActive = false;
    _pendingForwardRequest = null;
    cancelTimers();
  }

  void resetRequest({required bool retainReadable}) {
    if (_closed) return;
    cancelTimers();
    _paused = false;
    _planActive = false;
    _planCompleted = false;
    _attemptPublishedPageCount = 0;
    _pendingForwardRequest = null;
    if (!retainReadable) {
      _hasReadablePage = false;
      _targetReady = false;
      _restoreTargetPending = true;
      _availablePageCount = 0;
      _demandPageIndex = 0;
    }
  }

  void cancelTimers() {
    _cancelTargetTimer();
    _cancelBackgroundTimer();
  }

  void _cancelTargetTimer() {
    _targetDeadline = null;
    _targetTimer?.cancel();
    _targetTimer = null;
  }

  void _cancelBackgroundTimer() {
    _backgroundDeadline = null;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  void close() {
    if (_closed) return;
    cancelTimers();
    _pendingForwardRequest = null;
    _closed = true;
  }
}
