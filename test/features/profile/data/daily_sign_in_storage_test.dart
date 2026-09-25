import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/profile/data/daily_sign_in_storage.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';

void main() {
  const userId = '12345';

  test('account setting defaults on and stays isolated by UID', () async {
    final store = _MemoryPreferencesStore();
    final settings = SharedPreferencesDailyAutoSignInSettings(store);

    expect(await settings.isEnabled(userId), isTrue);
    await settings.setEnabled(userId, false);
    expect(await settings.isEnabled(userId), isFalse);
    expect(await settings.isEnabled('67890'), isTrue);
    expect(
      store.values[PreferenceKeys.dailyAutoSignInEnabledForUid(userId).name],
      false,
    );
  });

  test(
    'invalid setting storage fails closed instead of defaulting on',
    () async {
      final store = _MemoryPreferencesStore();
      store.values[PreferenceKeys.dailyAutoSignInEnabledForUid(userId).name] =
          'bad';
      final settings = SharedPreferencesDailyAutoSignInSettings(store);

      expect(
        settings.isEnabled(userId),
        throwsA(isA<DailySignInStorageException>()),
      );
    },
  );

  test(
    'pending survives process restart and pauses the next forum day',
    () async {
      final store = _MemoryPreferencesStore();
      final firstProcess = SharedPreferencesDailySignInAttemptLedger(store);
      final reservation = await firstProcess.reserve(
        userId: userId,
        forumDay: '20260925',
      );

      expect(reservation, isNotNull);
      final restored = SharedPreferencesDailySignInAttemptLedger(store);
      expect(
        (await restored.readCheckpoint(userId))?.state,
        DailySignInAttemptState.pending,
      );
      expect(
        await restored.automaticPolicy(userId: userId, forumDay: '20260925'),
        DailySignInAutomaticPolicy.blockedToday,
      );
      expect(
        await restored.automaticPolicy(userId: userId, forumDay: '20260926'),
        DailySignInAutomaticPolicy.pausedPreviousDay,
      );
      expect(
        await restored.automaticPolicy(userId: userId, forumDay: '20260927'),
        DailySignInAutomaticPolicy.eligible,
      );
    },
  );

  test('concurrent reservations yield one durable pending record', () async {
    final store = _MemoryPreferencesStore();
    final ledger = SharedPreferencesDailySignInAttemptLedger(store);
    final attempts = await Future.wait([
      ledger.reserve(userId: userId, forumDay: '20260925'),
      ledger.reserve(userId: userId, forumDay: '20260925'),
    ]);

    expect(attempts.whereType<DailySignInAttemptReservation>(), hasLength(1));
    expect(
      (await ledger.readCheckpoint(userId))?.state,
      DailySignInAttemptState.pending,
    );
  });

  test(
    'notSent restores prior unresolved attempt after explicit retry',
    () async {
      final store = _MemoryPreferencesStore();
      final ledger = SharedPreferencesDailySignInAttemptLedger(store);
      final first = (await ledger.reserve(
        userId: userId,
        forumDay: '20260925',
      ))!;
      await ledger.markUnknown(first);

      final retry = (await ledger.reserve(
        userId: userId,
        forumDay: '20260926',
        manualOverride: true,
      ))!;
      expect(
        (await ledger.readCheckpoint(userId))?.state,
        DailySignInAttemptState.pending,
      );
      await ledger.settleNotSent(retry);

      expect(
        await ledger.readCheckpoint(userId),
        const DailySignInAttemptCheckpoint(
          userId: userId,
          forumDay: '20260925',
          state: DailySignInAttemptState.unknown,
        ),
      );
      expect(
        await ledger.automaticPolicy(userId: userId, forumDay: '20260926'),
        DailySignInAutomaticPolicy.pausedPreviousDay,
      );
    },
  );

  test(
    'fresh signed read records status without changing old command result',
    () async {
      final store = _MemoryPreferencesStore();
      final ledger = SharedPreferencesDailySignInAttemptLedger(store);
      final reservation = (await ledger.reserve(
        userId: userId,
        forumDay: '20260925',
      ))!;

      await ledger.markConfirmedSigned(userId: userId, forumDay: '20260925');
      await ledger.markUnknown(reservation);
      expect(
        (await ledger.readCheckpoint(userId))?.state,
        DailySignInAttemptState.confirmedSigned,
      );
      expect(
        await ledger.automaticPolicy(userId: userId, forumDay: '20260926'),
        DailySignInAutomaticPolicy.eligible,
      );
    },
  );

  test(
    'corrupt and backward checkpoint cannot authorize another GET',
    () async {
      final store = _MemoryPreferencesStore();
      const key = '${TechnicalStorageKeys.dailySignInAttemptV1Prefix}$userId';
      store.values[key] = '{bad';
      final ledger = SharedPreferencesDailySignInAttemptLedger(store);
      expect(
        ledger.reserve(userId: userId, forumDay: '20260925'),
        throwsA(isA<DailySignInStorageException>()),
      );

      store.values[key] = jsonEncode({
        'schemaVersion': 1,
        'userId': userId,
        'forumDay': '20260926',
        'state': 'unknown',
      });
      expect(
        ledger.automaticPolicy(userId: userId, forumDay: '20260925'),
        throwsA(isA<DailySignInStorageException>()),
      );
      expect(
        ledger.reserve(
          userId: userId,
          forumDay: '20260925',
          manualOverride: true,
        ),
        throwsA(isA<DailySignInStorageException>()),
      );
    },
  );

  test('failed durable write never returns a reservation', () async {
    final store = _MemoryPreferencesStore()..failWrites = true;
    final ledger = SharedPreferencesDailySignInAttemptLedger(store);

    expect(
      ledger.reserve(userId: userId, forumDay: '20260925'),
      throwsA(isA<DailySignInStorageException>()),
    );
    expect(store.values, isEmpty);
  });

  test('invalid forum dates fail closed without using device date', () async {
    final ledger = SharedPreferencesDailySignInAttemptLedger(
      _MemoryPreferencesStore(),
    );
    for (final forumDay in ['20260230', '2026092', '00000101']) {
      expect(
        ledger.reserve(userId: userId, forumDay: forumDay),
        throwsA(isA<DailySignInStorageException>()),
      );
    }
  });
}

final class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> values = {};
  bool failWrites = false;

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    final value = values[key.name];
    return value is T ? value : null;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async =>
      values.containsKey(key.name);

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    if (failWrites) throw StateError('write failed');
    values[key.name] = value;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    if (failWrites) throw StateError('remove failed');
    values.remove(key.name);
  }
}
