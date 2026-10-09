import 'dart:async';

import 'package:y300/features/novel/domain/models/novel_reading_session.dart';

/// Owns producer authority and a single bounded chapter-end confirmation.
///
/// Layout and navigation adapters supply facts; this object never measures or
/// retains a Flutter context. It does not interpret a percentage as completion.
final class NovelReadingSessionCoordinator {
  NovelReadingSessionCoordinator({
    this.completionStability = const Duration(milliseconds: 250),
  });

  final Duration completionStability;
  NovelReadingSessionToken? _session;
  int _generation = 0;
  int _revision = 0;
  int _completionRevision = 0;
  bool _frontmost = false;
  bool _resumed = false;
  bool _bodyReady = false;
  bool _restoreSettled = false;
  bool _readOnlyCompatibilityRestore = false;
  bool _hasNavigated = false;
  bool _completionConfirmed = false;
  bool _disposed = false;
  Object? _positionIdentity;
  Object? _geometryIdentity;
  _CompletionObservation? _completionObservation;
  NovelReadingCommitLease? _emittedCompletion;
  Timer? _completionTimer;
  Completer<NovelReadingCommitLease?>? _completionWait;
  void Function(NovelReadingCommitLease)? _onComplete;

  NovelReadingSessionToken? get session => _session;

  NovelReadingSessionToken begin({
    required String novelId,
    required String episodeId,
    required NovelReadingSessionEntry entry,
  }) {
    if (_disposed) throw StateError('Reading coordinator is disposed');
    retire();
    return _session = NovelReadingSessionToken(
      novelId: novelId,
      episodeId: episodeId,
      generation: ++_generation,
      entry: entry,
    );
  }

  bool isCurrent(NovelReadingSessionToken token) =>
      !_disposed && identical(token, _session);

  void updateVisibility({required bool frontmost, required bool resumed}) {
    if (_disposed || (_frontmost == frontmost && _resumed == resumed)) return;
    _frontmost = frontmost;
    _resumed = resumed;
    // Authority is not revived when a covered route becomes visible again.
    _advanceRevision();
  }

  void updateReadiness(
    NovelReadingSessionToken token, {
    required bool bodyReady,
    required bool restoreSettled,
    bool readOnlyCompatibilityRestore = false,
  }) {
    if (!isCurrent(token)) return;
    // Finishing bootstrap cannot turn an approximate restore into a new record.
    final readOnly =
        _readOnlyCompatibilityRestore || readOnlyCompatibilityRestore;
    if (_bodyReady == bodyReady &&
        _restoreSettled == restoreSettled &&
        _readOnlyCompatibilityRestore == readOnly) {
      return;
    }
    _bodyReady = bodyReady;
    _restoreSettled = restoreSettled;
    _readOnlyCompatibilityRestore = readOnly;
    _advanceRevision();
  }

  /// Call only after a real, visible scroll, page turn or explicit seek.
  bool confirmNavigation(NovelReadingSessionToken token) {
    if (!isCurrent(token) ||
        !_frontmost ||
        !_resumed ||
        !_bodyReady ||
        !_restoreSettled) {
      return false;
    }
    _hasNavigated = true;
    _advanceRevision();
    return true;
  }

  NovelReadingCommitLease? positionLease(
    NovelReadingSessionToken token, {
    Object? positionIdentity,
  }) {
    if (!_canCommit(token)) return null;
    if (positionIdentity != null && _positionIdentity != positionIdentity) {
      _positionIdentity = positionIdentity;
      _advanceRevision();
    }
    return _lease(token);
  }

  /// Layout changes retire completion evidence, not a confirmed position.
  /// Lazy layout compensation is not a new reading navigation.
  void updateGeometry(
    NovelReadingSessionToken token,
    Object? geometryIdentity,
  ) {
    if (!isCurrent(token)) return;
    if (_geometryIdentity != geometryIdentity) {
      cancelPendingCompletion(token);
    }
    _geometryIdentity = geometryIdentity;
  }

  void reportCompletion(
    NovelReadingSessionToken token, {
    required bool bodyReady,
    required bool finalBoundaryKnown,
    required bool atBodyEnd,
    required bool wholeBodyVisible,
    required bool restoreSettled,
    required bool idle,
    required Object? geometryIdentity,
    required void Function(NovelReadingCommitLease) onComplete,
  }) {
    if (!isCurrent(token)) return;
    // Preserve compatibility protection supplied by the position adapter.
    updateReadiness(
      token,
      bodyReady: bodyReady,
      restoreSettled: restoreSettled,
      readOnlyCompatibilityRestore: _readOnlyCompatibilityRestore,
    );
    final observation = _CompletionObservation(
      finalBoundaryKnown: finalBoundaryKnown,
      atBodyEnd: atBodyEnd,
      wholeBodyVisible: wholeBodyVisible,
      idle: idle,
      geometryIdentity: geometryIdentity,
    );
    updateGeometry(token, geometryIdentity);
    if (_completionObservation != observation) {
      cancelPendingCompletion(token);
      _completionObservation = observation;
    }
    _onComplete = onComplete;
    if (_completionConfirmed ||
        !_canComplete(token, observation) ||
        _completionTimer != null) {
      return;
    }
    final lease = _lease(token, observation: observation);
    final completionWait = _completionWait =
        Completer<NovelReadingCommitLease?>();
    _completionTimer = Timer(completionStability, () {
      _completionTimer = null;
      var delivered = false;
      try {
        if (!lease.isValid) return;
        _completionConfirmed = true;
        _emittedCompletion = lease;
        final callback = _onComplete;
        _onComplete = null;
        callback?.call(lease);
        delivered = true;
      } finally {
        // A callback may retire this owner or start another confirmation. Only
        // the wait belonging to this timer can receive its result.
        _resolveCompletionWait(
          completionWait,
          delivered && lease.isValid ? lease : null,
        );
      }
    });
  }

  /// Joins an existing bounded confirmation without creating end evidence.
  /// Callers must still await their completion write before retiring the owner.
  Future<NovelReadingCommitLease?> waitForPendingCompletion(
    NovelReadingSessionToken token,
  ) {
    if (!isCurrent(token)) return Future.value(null);
    final emitted = _emittedCompletion;
    if (emitted != null && emitted.isValid) return Future.value(emitted);
    final wait = _completionWait;
    final observation = _completionObservation;
    return _completionTimer != null &&
            wait != null &&
            observation != null &&
            _canComplete(token, observation)
        ? wait.future
        : Future.value(null);
  }

  /// Allows a fresh observation after a failed or superseded queued write.
  /// No retry is started here, and an old session cannot unlock a new one.
  void rejectCompletion(NovelReadingCommitLease lease) {
    if (!isCurrent(lease.token) || !identical(lease, _emittedCompletion)) {
      return;
    }
    _completionConfirmed = false;
    _emittedCompletion = null;
    cancelPendingCompletion(lease.token);
  }

  void cancelPendingCompletion(NovelReadingSessionToken token) {
    if (!isCurrent(token)) return;
    _completionRevision += 1;
    _completionTimer?.cancel();
    _completionTimer = null;
    _completionObservation = null;
    _onComplete = null;
    _resolveCompletionWait(_completionWait, null);
  }

  void retire() {
    _completionTimer?.cancel();
    _completionTimer = null;
    _completionObservation = null;
    _onComplete = null;
    _session = null;
    _bodyReady = false;
    _restoreSettled = false;
    _readOnlyCompatibilityRestore = false;
    _hasNavigated = false;
    _completionConfirmed = false;
    _emittedCompletion = null;
    _positionIdentity = null;
    _geometryIdentity = null;
    _revision += 1;
    _completionRevision += 1;
    _resolveCompletionWait(_completionWait, null);
  }

  void dispose() {
    _disposed = true;
    retire();
  }

  bool _canCommit(NovelReadingSessionToken token) =>
      isCurrent(token) &&
      _frontmost &&
      _resumed &&
      _bodyReady &&
      _restoreSettled &&
      (_hasNavigated ||
          (!_readOnlyCompatibilityRestore &&
              token.entry != NovelReadingSessionEntry.readOnlyRestore &&
              token.entry != NovelReadingSessionEntry.bodyEnd));

  bool _canComplete(
    NovelReadingSessionToken token,
    _CompletionObservation observation,
  ) =>
      _canCommit(token) &&
      observation.finalBoundaryKnown &&
      observation.atBodyEnd &&
      observation.idle &&
      observation.geometryIdentity != null &&
      (_hasNavigated ||
          (observation.wholeBodyVisible &&
              (token.entry == NovelReadingSessionEntry.firstStart ||
                  token.entry == NovelReadingSessionEntry.explicitStart)));

  NovelReadingCommitLease _lease(
    NovelReadingSessionToken token, {
    _CompletionObservation? observation,
  }) {
    final revision = _revision;
    final completionRevision = _completionRevision;
    return NovelReadingCommitLease(
      token: token,
      revision: revision,
      isCurrent: () =>
          revision == _revision &&
          _canCommit(token) &&
          (observation == null ||
              (completionRevision == _completionRevision &&
                  _completionObservation == observation &&
                  _canComplete(token, observation))),
    );
  }

  void _advanceRevision() {
    _revision += 1;
    _completionRevision += 1;
    _completionTimer?.cancel();
    _completionTimer = null;
    _completionObservation = null;
    _onComplete = null;
    _resolveCompletionWait(_completionWait, null);
  }

  void _resolveCompletionWait(
    Completer<NovelReadingCommitLease?>? wait,
    NovelReadingCommitLease? lease,
  ) {
    if (wait == null) return;
    if (identical(wait, _completionWait)) _completionWait = null;
    if (!wait.isCompleted) wait.complete(lease);
  }
}

final class _CompletionObservation {
  const _CompletionObservation({
    required this.finalBoundaryKnown,
    required this.atBodyEnd,
    required this.wholeBodyVisible,
    required this.idle,
    required this.geometryIdentity,
  });

  final bool finalBoundaryKnown;
  final bool atBodyEnd;
  final bool wholeBodyVisible;
  final bool idle;
  final Object? geometryIdentity;

  @override
  bool operator ==(Object other) =>
      other is _CompletionObservation &&
      finalBoundaryKnown == other.finalBoundaryKnown &&
      atBodyEnd == other.atBodyEnd &&
      wholeBodyVisible == other.wholeBodyVisible &&
      idle == other.idle &&
      geometryIdentity == other.geometryIdentity;

  @override
  int get hashCode => Object.hash(
    finalBoundaryKnown,
    atBodyEnd,
    wholeBodyVisible,
    idle,
    geometryIdentity,
  );
}
