import 'dart:convert';

import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';

final class SharedPreferencesDailyAutoSignInSettings
    implements DailyAutoSignInSettings {
  SharedPreferencesDailyAutoSignInSettings(this._store);

  final PreferencesStore _store;

  @override
  Future<bool> isEnabled(String userId) async {
    _validateUserId(userId);
    final key = PreferenceKeys.dailyAutoSignInEnabledForUid(userId);
    try {
      final value = await _store.read(key);
      if (value != null) return value;
      if (await _store.contains(key)) {
        throw const DailySignInStorageException();
      }
      return true;
    } on Object {
      throw const DailySignInStorageException();
    }
  }

  @override
  Future<void> setEnabled(String userId, bool enabled) async {
    _validateUserId(userId);
    try {
      await _store.write(
        PreferenceKeys.dailyAutoSignInEnabledForUid(userId),
        enabled,
      );
    } on Object {
      throw const DailySignInStorageException();
    }
  }
}

final class SharedPreferencesDailySignInAttemptLedger
    implements DailySignInAttemptLedger {
  SharedPreferencesDailySignInAttemptLedger(this._store);

  final PreferencesStore _store;
  final Map<String, DailySignInAttemptReservation> _active = {};
  Future<void> _tail = Future<void>.value();
  int _nextToken = 0;

  @override
  Future<DailySignInAttemptCheckpoint?> readCheckpoint(String userId) =>
      _serial(() => _read(userId));

  @override
  Future<DailySignInAutomaticPolicy> automaticPolicy({
    required String userId,
    required String forumDay,
  }) => _serial(() async {
    final date = _parseForumDay(forumDay);
    final checkpoint = await _read(userId);
    return _policy(checkpoint, date);
  });

  @override
  Future<DailySignInAttemptReservation?> reserve({
    required String userId,
    required String forumDay,
    bool manualOverride = false,
  }) => _serial(() async {
    final date = _parseForumDay(forumDay);
    final previous = await _read(userId);
    final policy = _policy(previous, date);
    if (_active.containsKey(userId)) return null;
    if (!manualOverride && policy != DailySignInAutomaticPolicy.eligible) {
      return null;
    }
    if (manualOverride &&
        previous?.forumDay == forumDay &&
        previous?.state == DailySignInAttemptState.confirmedSigned) {
      return null;
    }

    // The durable pending record must exist before the caller authorizes the
    // one-shot GET. A crash after this write can only cause a conservative
    // read-only block on the next launch.
    await _write(
      DailySignInAttemptCheckpoint(
        userId: userId,
        forumDay: forumDay,
        state: DailySignInAttemptState.pending,
      ),
    );
    final reservation = DailySignInAttemptReservation(
      userId: userId,
      forumDay: forumDay,
      token: ++_nextToken,
      previous: previous,
    );
    _active[userId] = reservation;
    return reservation;
  });

  @override
  Future<void> settleNotSent(DailySignInAttemptReservation reservation) =>
      _serial(() async {
        if (!_isActive(reservation)) return;
        final current = await _read(reservation.userId);
        if (current?.forumDay == reservation.forumDay &&
            current?.state == DailySignInAttemptState.pending) {
          if (reservation.previous case final previous?) {
            await _write(previous);
          } else {
            await _remove(reservation.userId);
          }
        }
        _active.remove(reservation.userId);
      });

  @override
  Future<void> markUnknown(DailySignInAttemptReservation reservation) =>
      _serial(() async {
        if (!_isActive(reservation)) return;
        final current = await _read(reservation.userId);
        if (current?.forumDay == reservation.forumDay &&
            current?.state == DailySignInAttemptState.confirmedSigned) {
          _active.remove(reservation.userId);
          return;
        }
        await _write(
          DailySignInAttemptCheckpoint(
            userId: reservation.userId,
            forumDay: reservation.forumDay,
            state: DailySignInAttemptState.unknown,
          ),
        );
        _active.remove(reservation.userId);
      });

  @override
  Future<void> markConfirmedSigned({
    required String userId,
    required String forumDay,
  }) => _serial(() async {
    final date = _parseForumDay(forumDay);
    final current = await _read(userId);
    if (current != null && date.isBefore(_parseForumDay(current.forumDay))) {
      return;
    }
    if (current?.forumDay != forumDay ||
        current?.state != DailySignInAttemptState.confirmedSigned) {
      await _write(
        DailySignInAttemptCheckpoint(
          userId: userId,
          forumDay: forumDay,
          state: DailySignInAttemptState.confirmedSigned,
        ),
      );
    }
    _active.remove(userId);
  });

  DailySignInAutomaticPolicy _policy(
    DailySignInAttemptCheckpoint? checkpoint,
    DateTime forumDate,
  ) {
    if (checkpoint == null) return DailySignInAutomaticPolicy.eligible;
    final days = forumDate
        .difference(_parseForumDay(checkpoint.forumDay))
        .inDays;
    if (days < 0) throw const DailySignInStorageException();
    if (days == 0) return DailySignInAutomaticPolicy.blockedToday;
    if (days == 1 && checkpoint.isUnresolved) {
      return DailySignInAutomaticPolicy.pausedPreviousDay;
    }
    return DailySignInAutomaticPolicy.eligible;
  }

  bool _isActive(DailySignInAttemptReservation reservation) =>
      identical(_active[reservation.userId], reservation);

  Future<DailySignInAttemptCheckpoint?> _read(String userId) async {
    final key = _checkpointKey(userId);
    try {
      final encoded = await _store.read(key);
      if (encoded == null) {
        if (await _store.contains(key)) {
          throw const DailySignInStorageException();
        }
        return null;
      }
      return _decode(encoded, userId);
    } on Object {
      throw const DailySignInStorageException();
    }
  }

  Future<void> _write(DailySignInAttemptCheckpoint checkpoint) async {
    try {
      await _store.write(
        _checkpointKey(checkpoint.userId),
        _encode(checkpoint),
      );
    } on Object {
      throw const DailySignInStorageException();
    }
  }

  Future<void> _remove(String userId) async {
    try {
      await _store.remove(_checkpointKey(userId));
    } on Object {
      throw const DailySignInStorageException();
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final future = _tail.then((_) => operation());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }
}

PreferenceKey<String> _checkpointKey(String userId) {
  _validateUserId(userId);
  return PreferenceKey<String>(
    '${TechnicalStorageKeys.dailySignInAttemptV1Prefix}$userId',
  );
}

void _validateUserId(String userId) {
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(userId)) {
    throw const DailySignInStorageException();
  }
}

DateTime _parseForumDay(String forumDay) {
  if (!RegExp(r'^[0-9]{8}$').hasMatch(forumDay)) {
    throw const DailySignInStorageException();
  }
  final year = int.parse(forumDay.substring(0, 4));
  final month = int.parse(forumDay.substring(4, 6));
  final day = int.parse(forumDay.substring(6, 8));
  if (year == 0) throw const DailySignInStorageException();
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw const DailySignInStorageException();
  }
  return date;
}

String _encode(DailySignInAttemptCheckpoint checkpoint) => jsonEncode({
  'schemaVersion': 1,
  'userId': checkpoint.userId,
  'forumDay': checkpoint.forumDay,
  'state': checkpoint.state.name,
});

DailySignInAttemptCheckpoint _decode(String encoded, String expectedUserId) {
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 4 ||
        decoded['schemaVersion'] != 1 ||
        decoded['userId'] != expectedUserId ||
        decoded['forumDay'] is! String ||
        decoded['state'] is! String) {
      throw const DailySignInStorageException();
    }
    _parseForumDay(decoded['forumDay'] as String);
    final state = DailySignInAttemptState.values.firstWhere(
      (item) => item.name == decoded['state'],
    );
    return DailySignInAttemptCheckpoint(
      userId: expectedUserId,
      forumDay: decoded['forumDay'] as String,
      state: state,
    );
  } on Object {
    throw const DailySignInStorageException();
  }
}
