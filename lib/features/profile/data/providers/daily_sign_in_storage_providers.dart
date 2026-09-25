import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/profile/data/daily_sign_in_storage.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';

final dailySignInAttemptLedgerProvider = Provider<DailySignInAttemptLedger>(
  (ref) => SharedPreferencesDailySignInAttemptLedger(
    ref.watch(preferencesStoreProvider),
  ),
);

final dailyAutoSignInSettingsProvider = Provider<DailyAutoSignInSettings>(
  (ref) => SharedPreferencesDailyAutoSignInSettings(
    ref.watch(preferencesStoreProvider),
  ),
);
