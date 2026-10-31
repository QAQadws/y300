import 'dart:async';

import '../models/novel_reader_pagination_exception.dart';
import 'novel_reader_pagination_cancellation.dart';
import 'novel_reader_pagination_performance_policy.dart';

/// Unique waiting intent, scoped to one watchdog/layout. No page or owner held.
final class NovelReaderNativeTargetWait {
  NovelReaderNativeTargetWait._();
}

typedef NovelReaderNativeDeadlineCallback = void Function(
  NovelReaderPaginationException error,
  NovelReaderNativeTargetWait? target,
);

/// Recovery deadlines only; never changes modes, cancels parent/source or
/// confirms a reading position. Host retires pending work while retaining its
/// mounted view, then creates a fresh request/watchdog for an explicit retry.
final class NovelReaderNativePaginationWatchdog {
  factory NovelReaderNativePaginationWatchdog({
    required NovelReaderPaginationCancellationToken parent,
    required NovelReaderNativeDeadlineCallback onExpired,
    NovelReaderPaginationPerformancePolicy policy =
        const NovelReaderPaginationPerformancePolicy(),
    Duration Function()? elapsed,
  }) {
    parent.throwIfCancelled();
    if (policy.targetPageWait <= Duration.zero ||
        policy.backgroundIdle <= Duration.zero) {
      throw ArgumentError('Invalid native pagination deadlines');
    }
    final watch = NovelReaderNativePaginationWatchdog._(
      onExpired,
      policy,
      elapsed,
    );
    final remove = parent.onCancel(watch.close);
    if (watch._closed) {
      remove();
    } else {
      watch._removeParent = remove;
    }
    return watch;
  }

  NovelReaderNativePaginationWatchdog._(
    this._onExpired,
    this.policy,
    this._readElapsed,
  ) : _remaining = policy.backgroundIdle;
  final NovelReaderPaginationPerformancePolicy policy;
  final _clock = Stopwatch()..start();
  Duration Function()? _readElapsed;
  NovelReaderNativeDeadlineCallback? _onExpired;
  void Function()? _removeParent;
  Timer? _targetTimer;
  Timer? _backgroundTimer;
  NovelReaderNativeTargetWait? _target;
  int _pageCount = 0;
  int _backgroundGeneration = 0;
  bool _complete = false;
  bool _readable = false;
  bool _deferring = false;
  bool _closed = false;
  bool _expired = false;
  Duration _remaining;
  Duration? _backgroundStarted;

  bool get isClosed => _closed;
  bool get isExpired => _expired;
  bool get isWaitingForTarget => _target != null;
  Duration get _elapsed => _readElapsed?.call() ?? _clock.elapsed;

  NovelReaderNativeTargetWait startTarget() {
    _guard();
    _targetTimer?.cancel();
    _pauseBackground();
    final ticket = NovelReaderNativeTargetWait._();
    _target = ticket;
    if (policy.enforceBudgets) {
      _targetTimer = Timer(policy.targetPageWait, () {
        if (!_closed && identical(_target, ticket)) {
          _expire(
            const NovelReaderPaginationException(
              code: 'targetPageWaitExceeded',
              message: 'The requested page is not available within the waiting budget.',
            ),
            ticket,
          );
        }
      });
    }
    return ticket;
  }

  /// Call after the current target is actually readable, including preparation.
  /// Neither publication/EOF nor an old ticket can satisfy this intent.
  bool markReadable(NovelReaderNativeTargetWait ticket) {
    if (_closed || !identical(_target, ticket)) return false;
    _targetTimer?.cancel();
    _targetTimer = null;
    _target = null;
    _readable = true;
    _remaining = policy.backgroundIdle;
    _syncBackground();
    return true;
  }

  void publication({required int pageCount, required bool isComplete}) {
    _guard();
    if (pageCount < _pageCount ||
        (_complete && (!isComplete || pageCount != _pageCount))) {
      throw StateError('Native deadline prefix regressed');
    }
    final grew = pageCount > _pageCount;
    _pageCount = pageCount;
    _complete = isComplete;
    if (grew) {
      _pauseBackground();
      _remaining = policy.backgroundIdle;
    }
    _syncBackground();
  }

  /// Count active no-publication time only. Repeated idle/promote transitions
  /// preserve the remaining budget instead of indefinitely resetting a stall.
  void setDeferring(bool value) {
    _guard();
    if (value == _deferring) return;
    _deferring = value;
    _syncBackground();
  }

  void _syncBackground() {
    if (!policy.enforceBudgets ||
        !_readable ||
        _target != null ||
        _complete ||
        _deferring) {
      _pauseBackground();
      return;
    }
    if (_backgroundTimer != null) return;
    final generation = ++_backgroundGeneration;
    _backgroundStarted = _elapsed;
    _backgroundTimer = Timer(_remaining, () {
      if (!_closed && generation == _backgroundGeneration) {
        _expire(
          const NovelReaderPaginationException(
            code: 'backgroundPaginationIdle',
            message: 'Background pagination stopped publishing readable pages.',
          ),
          null,
        );
      }
    });
  }

  void _pauseBackground() {
    final started = _backgroundStarted;
    if (started != null) {
      final spent = _elapsed - started;
      if (spent > Duration.zero) {
        _remaining = spent < _remaining ? _remaining - spent : Duration.zero;
      }
    }
    _backgroundStarted = null;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _backgroundGeneration++;
  }

  void _expire(
    NovelReaderPaginationException error,
    NovelReaderNativeTargetWait? ticket,
  ) {
    _expired = true;
    final callback = _onExpired;
    close();
    callback?.call(error, ticket);
  }

  void _guard() {
    if (_closed) throw StateError('Native pagination watchdog is closed');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _targetTimer?.cancel();
    _targetTimer = null;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _backgroundStarted = null;
    _backgroundGeneration++;
    _target = null;
    _onExpired = null;
    _readElapsed = null;
    _clock.stop();
    _removeParent?.call();
    _removeParent = null;
  }
}
