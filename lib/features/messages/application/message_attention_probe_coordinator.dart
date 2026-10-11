import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_probe_policy.dart';
import 'package:y300/features/messages/application/message_attention_state.dart';

export 'message_attention_probe_policy.dart';

typedef MessageAttentionProbe =
    Future<bool> Function(
      MessageAttentionOwner owner,
      ForumRequestCancellation cancellation,
    );
typedef MessageAttentionProbeTimer =
    Timer Function(Duration delay, void Function() callback);

/// Coordinates optional reads without owning transport, UI or arrival state.
/// Complete accepted observations enter through [recordFreshSample]; a probe
/// returning success alone cannot satisfy a consumption calibration barrier.
final class MessageAttentionProbeCoordinator {
  MessageAttentionProbeCoordinator({
    required MessageAttentionProbe probe,
    this.policy = const MessageAttentionProbePolicy(),
    DateTime Function()? now,
    MessageAttentionProbeTimer? createTimer,
  }) : _probe = probe,
       _now = now ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new {
    policy.validate();
  }

  final MessageAttentionProbePolicy policy;
  final MessageAttentionProbe _probe;
  final DateTime Function() _now;
  final MessageAttentionProbeTimer _createTimer;
  MessageAttentionOwner? _owner;
  bool _foreground = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _ownerStartedAt;
  DateTime? _freshAt;
  int _freshSequence = -1;
  int? _calibrateAfter;
  int _calibrationRevision = 0;
  int _failures = 0;
  DateTime? _retryAfter;
  DateTime? _lastAttemptAt;
  bool _pending = false;
  int _attempts = 0;
  DateTime? _notBefore;
  _ProbeFlight? _flight;
  Timer? _timer;
  Object? _timerIdentity;

  bool get isProbing => _flight != null;

  void setEligibility({
    required MessageAttentionOwner? owner,
    required bool foreground,
  }) {
    if (_disposed) return;
    final ownerChanged = owner != _owner;
    final resumed = !_foreground && foreground;
    if (!ownerChanged && _foreground == foreground) return;
    if (ownerChanged || !foreground) _retireWork();
    _owner = owner;
    _foreground = foreground;
    if (ownerChanged) {
      _ownerStartedAt = owner == null ? null : _now();
      _freshAt = _lastAttemptAt = _retryAfter = null;
      _freshSequence = -1;
      _calibrateAfter = null;
      _calibrationRevision = 0;
      _failures = 0;
    }
    if (_eligible && (ownerChanged || resumed)) {
      if (_calibrateAfter != null || _isStale) {
        _armOpportunity(policy.coalesceDelay);
      } else {
        _schedule();
      }
    }
  }

  /// Only complete evidence accepted for the current owner may call this.
  void recordFreshSample({
    required MessageAttentionOwner owner,
    required int sequence,
  }) {
    if (_disposed ||
        owner != _owner ||
        sequence < 1 ||
        sequence <= _freshSequence) {
      return;
    }
    _freshSequence = sequence;
    _freshAt = _now();
    _failures = 0;
    _retryAfter = null;
    if (_calibrateAfter != null && sequence > _calibrateAfter!) {
      _calibrateAfter = null;
    }
    if (_calibrateAfter == null) {
      _pending = false;
      _attempts = 0;
      _notBefore = null;
    }
    _schedule();
  }

  /// One deferred calibration covers multiple successful reads. A sample
  /// launched before the latest consumption success cannot cancel this need.
  void requestCalibration({
    required MessageAttentionOwner owner,
    required int minimumSequence,
  }) {
    if (_disposed || owner != _owner || minimumSequence < 0) return;
    if (_calibrateAfter == null || minimumSequence > _calibrateAfter!) {
      _calibrateAfter = minimumSequence;
      ++_calibrationRevision;
      _attempts = 0;
    }
    _armOpportunity(policy.coalesceDelay);
  }

  bool get _eligible => !_disposed && _foreground && _owner != null;
  bool get _isStale =>
      _freshAt == null || _now().difference(_freshAt!) >= policy.freshness;

  void _armOpportunity(Duration delay) {
    if (!_pending && _flight == null) _attempts = 0;
    _pending = true;
    _notBefore = _later(_notBefore, _now().add(delay));
    _schedule();
  }

  void _schedule() {
    _cancelTimer();
    if (!_eligible || _flight != null) return;
    if (_pending && _calibrateAfter == null && !_isStale) {
      _pending = false;
      _attempts = 0;
      _notBefore = null;
    }
    if (_pending) {
      final due = _later(_notBefore, _retryAfter) ?? _now();
      _scheduleAt(due, _startProbe);
      return;
    }
    final interval = policy.foregroundInterval;
    if (interval == null) return;
    final baseline = _later(_freshAt, _lastAttemptAt) ?? _ownerStartedAt!;
    final due = _later(baseline.add(interval), _retryAfter)!;
    _scheduleAt(due, () => _armOpportunity(Duration.zero));
  }

  void _scheduleAt(DateTime due, void Function() callback) {
    final identity = Object();
    _timerIdentity = identity;
    final delay = due.difference(_now());
    _timer = _createTimer(delay.isNegative ? Duration.zero : delay, () {
      if (_disposed || !identical(_timerIdentity, identity)) return;
      _timer = null;
      _timerIdentity = null;
      callback();
    });
  }

  void _startProbe() {
    if (!_eligible || _flight != null || !_pending) return;
    if (_calibrateAfter == null && !_isStale) {
      _pending = false;
      _schedule();
      return;
    }
    _pending = false;
    _notBefore = null;
    ++_attempts;
    _lastAttemptAt = _now();
    final flight = _ProbeFlight(
      _owner!,
      _generation,
      _freshSequence,
      _calibrationRevision,
    );
    _flight = flight;
    unawaited(_runProbe(flight));
  }

  Future<void> _runProbe(_ProbeFlight flight) async {
    var succeeded = false;
    try {
      succeeded = await _probe(flight.owner, flight.cancellation);
    } on Object {
      // This is optional calibration. Failure retains the existing dot state.
    }
    if (_disposed ||
        !identical(_flight, flight) ||
        flight.generation != _generation ||
        flight.owner != _owner) {
      return;
    }
    _flight = null;
    if (_freshSequence > flight.freshSequence && _calibrateAfter == null) {
      // A normal read can finish calibration before this probe completes.
      // Its later failure must not impose a cooldown on the next real read.
      _failures = 0;
      _retryAfter = null;
      _pending = false;
      _attempts = 0;
      _notBefore = null;
      _schedule();
      return;
    }
    if (flight.calibrationRevision != _calibrationRevision) {
      // A newer successful consumption owns a new bounded opportunity. The
      // old probe cannot spend that opportunity's budget or report its failure.
      _pending = true;
      _attempts = 0;
      _notBefore ??= _now().add(policy.coalesceDelay);
      _schedule();
      return;
    }
    if (succeeded) {
      _failures = 0;
      _retryAfter = null;
      if (_calibrateAfter != null && _attempts < policy.maximumAttempts) {
        _pending = true;
        _notBefore = _later(_notBefore, _now().add(policy.coalesceDelay));
      }
    } else {
      _retryAfter = _now().add(policy.retryDelay(++_failures));
      if ((_calibrateAfter != null || _isStale) &&
          _attempts < policy.maximumAttempts) {
        _pending = true;
      }
    }
    // A consumed request arriving during the flight may have armed a new need.
    // Otherwise exhausted attempts await the next real lifecycle/read event.
    if (_attempts >= policy.maximumAttempts) _pending = false;
    _schedule();
  }

  DateTime? _later(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }

  void _cancelTimer() {
    _timerIdentity = null;
    _timer?.cancel();
    _timer = null;
  }

  void _retireWork() {
    ++_generation;
    _cancelTimer();
    _flight?.cancellation.cancel();
    _flight = null;
    _pending = false;
    _attempts = 0;
    _notBefore = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retireWork();
    _owner = null;
    _calibrateAfter = null;
  }
}

final class _ProbeFlight {
  _ProbeFlight(
    this.owner,
    this.generation,
    this.freshSequence,
    this.calibrationRevision,
  );

  final MessageAttentionOwner owner;
  final int generation;
  final int freshSequence;
  final int calibrationRevision;
  final ForumRequestCancellation cancellation = ForumRequestCancellation();
}
