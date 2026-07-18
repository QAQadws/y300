import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/features/library_shared/data/repositories/sync_diagnostic_settings_repository.dart';

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

  test('release policy ignores a persisted debug manual-mode flag', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppStorageKeys.syncDiagnosticManualMode: true,
    });
    final releaseRepository = SharedPrefsSyncDiagnosticSettingsRepository(
      diagnosticsEnabled: false,
    );

    expect(await releaseRepository.loadManualModeEnabled(), isFalse);
    await releaseRepository.setManualModeEnabled(false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppStorageKeys.syncDiagnosticManualMode), isTrue);
  });
}
