/// A checkpoint records one account's latest known forum day. `pending` is
/// deliberately treated like `unknown` after a process restart.
enum DailySignInAttemptState { pending, unknown, confirmedSigned }

final class DailySignInAttemptCheckpoint {
  const DailySignInAttemptCheckpoint({
    required this.userId,
    required this.forumDay,
    required this.state,
  });

  final String userId;
  final String forumDay;
  final DailySignInAttemptState state;

  bool get isUnresolved =>
      state == DailySignInAttemptState.pending ||
      state == DailySignInAttemptState.unknown;

  @override
  bool operator ==(Object other) =>
      other is DailySignInAttemptCheckpoint &&
      other.userId == userId &&
      other.forumDay == forumDay &&
      other.state == state;

  @override
  int get hashCode => Object.hash(userId, forumDay, state);
}

enum DailySignInAutomaticPolicy { eligible, blockedToday, pausedPreviousDay }

/// The previous record is retained so a pre-send `notSent` can be rolled back
/// without discarding an earlier unresolved attempt.
final class DailySignInAttemptReservation {
  const DailySignInAttemptReservation({
    required this.userId,
    required this.forumDay,
    required this.token,
    required this.previous,
  });

  final String userId;
  final String forumDay;
  final int token;
  final DailySignInAttemptCheckpoint? previous;
}

abstract interface class DailySignInAttemptLedger {
  Future<DailySignInAttemptCheckpoint?> readCheckpoint(String userId);

  Future<DailySignInAutomaticPolicy> automaticPolicy({
    required String userId,
    required String forumDay,
  });

  /// Returns null when policy blocks a send. Persistence errors throw before
  /// the caller may send a network command.
  Future<DailySignInAttemptReservation?> reserve({
    required String userId,
    required String forumDay,
    bool manualOverride = false,
  });

  Future<void> settleNotSent(DailySignInAttemptReservation reservation);

  Future<void> markUnknown(DailySignInAttemptReservation reservation);

  Future<void> markConfirmedSigned({
    required String userId,
    required String forumDay,
  });
}

abstract interface class DailyAutoSignInSettings {
  Future<bool> isEnabled(String userId);

  Future<void> setEnabled(String userId, bool enabled);
}

final class DailySignInStorageException implements Exception {
  const DailySignInStorageException();

  @override
  String toString() => 'DailySignInStorageException';
}
