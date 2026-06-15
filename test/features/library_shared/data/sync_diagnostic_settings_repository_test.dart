import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_settings_repository.dart';

void main() {
  late SharedPrefsSyncDiagnosticSettingsRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = SharedPrefsSyncDiagnosticSettingsRepository();
  });

  test('loadManualModeEnabled defaults to false', () async {
    expect(await repository.loadManualModeEnabled(), isFalse);
  });

  test('setManualModeEnabled persists value', () async {
    await repository.setManualModeEnabled(true);

    expect(await repository.loadManualModeEnabled(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppStorageKeys.syncDiagnosticManualMode), isTrue);
  });
}
