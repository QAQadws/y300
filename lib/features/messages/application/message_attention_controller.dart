import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/application/message_attention_state.dart';

export 'message_attention_state.dart';

enum MessageAttentionConsumptionKind { privateMessages, notifications }

/// Accepted complete evidence, including repeated values with no UI change.
final class MessageAttentionFreshSample {
  const MessageAttentionFreshSample({
    required this.owner,
    required this.sequence,
  });

  final MessageAttentionOwner owner;
  final int sequence;
}

/// Merges fresh arrival evidence without networking or consuming forum hints.
///
/// The publishing host binds [MessageAttentionOwner] and the sequence when a
/// request starts, and verifies its current owner before calling [accept].
final class MessageAttentionController
    extends ValueNotifier<MessageAttentionState> {
  MessageAttentionController() : super(const MessageAttentionState());

  static const _unknown = ForumMessageAttentionState.unknown;
  static const _absent = ForumMessageAttentionState.absent;
  static const _present = ForumMessageAttentionState.present;

  MessageAttentionOwner? _owner;
  int _requestSequence = 0;
  int _privateSequence = -1;
  int _notificationSequence = -1;
  int _combinedSequence = -1;
  int _privateConsumptionBarrier = 0;
  int _notificationConsumptionBarrier = 0;
  int _completeSequence = -1;
  final _freshSamples = StreamController<MessageAttentionFreshSample>.broadcast(
    sync: true,
  );
  ForumMessageAttentionState _privateMessages = _unknown;
  ForumMessageAttentionState _notifications = _unknown;
  ForumMessageAttentionState _combinedHint = _unknown;
  int? _notificationCount;
  int _attentionEpoch = 0;
  int _acknowledgedMoreEpoch = 0;
  bool _moreVisible = false;
  final Object _defaultVisibilityOwner = Object();
  Object? _moreVisibilityOwner;
  bool _disposed = false;

  /// Monotonic local request order; it is not a server arrival version.
  int nextRequestSequence() => ++_requestSequence;

  Stream<MessageAttentionFreshSample> get freshSamples => _freshSamples.stream;
  int get latestCompleteSequence => _completeSequence;

  /// Successful business reads establish order, not a synthetic zero. Taking
  /// the current maximum also retires samples started while the read was in flight.
  int? recordConsumption({
    required MessageAttentionOwner owner,
    required MessageAttentionConsumptionKind kind,
  }) {
    if (_disposed || _owner != owner) return null;
    switch (kind) {
      case MessageAttentionConsumptionKind.privateMessages:
        _privateConsumptionBarrier = _requestSequence;
      case MessageAttentionConsumptionKind.notifications:
        _notificationConsumptionBarrier = _requestSequence;
    }
    return _requestSequence;
  }

  /// Identity loss, same-UID re-login and a new source lifetime discard hints.
  void setOwner(MessageAttentionOwner? owner) {
    if (_disposed || owner == _owner) return;
    _owner = owner;
    _privateSequence = _notificationSequence = _combinedSequence = -1;
    _privateConsumptionBarrier = _notificationConsumptionBarrier = 0;
    _completeSequence = -1;
    _privateMessages = _notifications = _combinedHint = _unknown;
    _notificationCount = null;
    _attentionEpoch = _acknowledgedMoreEpoch = 0;
    _publish();
  }

  /// Applies only fields whose coverage is newer than retained evidence.
  void accept(
    ForumMessageAttentionObservation observation, {
    required MessageAttentionOwner owner,
    required int sequence,
  }) {
    if (_disposed ||
        owner != _owner ||
        observation.viewerUserId != owner.sessionOwner.uid ||
        sequence < 1) {
      return;
    }
    if (observation.combinedHint != _unknown &&
        observation.combined == _unknown) {
      return;
    }
    if (sequence > _requestSequence) _requestSequence = sequence;

    final previousCombined = _combined;
    final canAcceptPrivate =
        observation.privateMessages != _unknown &&
        sequence > _privateSequence &&
        sequence > _combinedSequence &&
        sequence > _privateConsumptionBarrier;
    final canAcceptNotifications =
        observation.notifications != _unknown &&
        sequence > _notificationSequence &&
        sequence > _combinedSequence &&
        sequence > _notificationConsumptionBarrier;
    final canAcceptCombined =
        observation.combinedHint != _unknown &&
        sequence > _combinedSequence &&
        sequence > _privateConsumptionBarrier &&
        sequence > _notificationConsumptionBarrier &&
        (observation.combinedHint == _absent ||
            (sequence > _privateSequence && sequence > _notificationSequence));
    var arrivalChanged = false;
    if (canAcceptPrivate) {
      arrivalChanged |=
          _privateMessages == _absent &&
          observation.privateMessages == _present;
      _privateMessages = observation.privateMessages;
      _privateSequence = sequence;
    }

    if (canAcceptNotifications) {
      arrivalChanged |=
          _notifications == _absent && observation.notifications == _present;
      final count = _reliableNotificationCount(observation);
      arrivalChanged |=
          _notificationCount != null &&
          count != null &&
          count > _notificationCount!;
      _notifications = observation.notifications;
      _notificationSequence = sequence;
      // A countless known hint breaks the growth baseline. Restoring a count
      // later improves knowledge but cannot prove that a new arrival occurred.
      _notificationCount = count;
    }

    if (canAcceptCombined) {
      _combinedHint = observation.combinedHint;
      _combinedSequence = sequence;
      if (_combinedHint == _absent) {
        // Aggregate absence covers only older category evidence. Keeping a
        // later positive avoids clearing it; this negative baseline can still
        // clear the aggregate when that category subsequently becomes absent.
        if (_privateSequence < sequence) {
          _privateMessages = _unknown;
          _privateSequence = sequence;
        }
        if (_notificationSequence < sequence) {
          _notifications = _unknown;
          _notificationSequence = sequence;
          _notificationCount = null;
        }
      } else {
        // A later source may only identify the already observed aggregate
        // arrival. Older category negatives cannot count that upgrade again.
        if (_privateSequence < sequence && _privateMessages == _absent) {
          _privateMessages = _unknown;
        }
        if (_notificationSequence < sequence) {
          if (_notifications == _absent) _notifications = _unknown;
          _notificationCount = null;
        }
      }
    }

    if (_combinedHint != _unknown &&
        _privateMessages != _unknown &&
        _notifications != _unknown &&
        _privateSequence > _combinedSequence &&
        _notificationSequence > _combinedSequence &&
        _privateSequence > _privateConsumptionBarrier &&
        _notificationSequence > _notificationConsumptionBarrier) {
      // New category coverage replaces a historical mobile aggregate, so a
      // complete inactive API/desktop snapshot can actually clear its dot.
      _combinedHint = _unknown;
    }

    final combined = _combined;
    if (combined == _present &&
        (previousCombined != _present || arrivalChanged)) {
      ++_attentionEpoch;
    }
    if (_moreVisible && combined == _present) {
      _acknowledgedMoreEpoch = _attentionEpoch;
    }
    _publish();
    if (!_disposed &&
        _owner == owner &&
        (canAcceptCombined || (canAcceptPrivate && canAcceptNotifications)) &&
        sequence > _completeSequence) {
      _completeSequence = sequence;
      _freshSamples.add(
        MessageAttentionFreshSample(owner: owner, sequence: sequence),
      );
    }
  }

  /// The shell supplies actual route and foreground visibility, not mounting.
  /// Retiring visibility never notifies, so it is safe during host teardown.
  void setMoreVisible(bool visible, {Object? visibilityOwner}) {
    if (_disposed) return;
    final identity = visibilityOwner ?? _defaultVisibilityOwner;
    if (!visible && _moreVisibilityOwner != identity) return;
    _moreVisibilityOwner = visible ? identity : null;
    _moreVisible = visible;
    if (visible) acknowledgeMore();
  }

  /// Only acknowledges the current local round; no server hint is modified.
  void acknowledgeMore() {
    if (_disposed || _combined != _present) return;
    _acknowledgedMoreEpoch = _attentionEpoch;
    _publish();
  }

  ForumMessageAttentionState get _combined {
    // Older positives were retired when combined absence was accepted. A
    // retained positive therefore either remains compatible with the combined
    // hint or is newer than it and must take precedence over that absence.
    if (_privateMessages == _present || _notifications == _present) {
      return _present;
    }
    if (_combinedHint != _unknown) return _combinedHint;
    if (_privateMessages == _absent && _notifications == _absent) {
      return _absent;
    }
    return _unknown;
  }

  int? _reliableNotificationCount(
    ForumMessageAttentionObservation observation,
  ) => switch (observation.source) {
    // Both supported forms report the same complete notification total. A
    // representation switch with an unchanged count does not create a round.
    ForumMessageAttentionSource.api ||
    ForumMessageAttentionSource.desktopHtml => observation.notificationCount,
    ForumMessageAttentionSource.mobileHtml => null,
  };

  void _publish() {
    value = MessageAttentionState(
      owner: _owner,
      privateMessages: _privateMessages,
      notifications: _notifications,
      combined: _combined,
      notificationCount: _notificationCount,
      attentionEpoch: _attentionEpoch,
      acknowledgedMoreEpoch: _acknowledgedMoreEpoch,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_freshSamples.close());
    super.dispose();
  }
}
