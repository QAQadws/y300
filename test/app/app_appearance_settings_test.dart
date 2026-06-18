import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/settings/app_appearance_settings_repository.dart';
import 'package:y300/core/config/app_storage_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsAppAppearanceSettingsRepository', () {
    test('defaults to light when no preference is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPrefsAppAppearanceSettingsRepository();

      final settings = await repository.load();

      expect(settings.themePreference, AppThemePreference.light);
    });

    test('saves and loads all theme preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPrefsAppAppearanceSettingsRepository();

      for (final preference in AppThemePreference.values) {
        await repository.save(AppAppearanceSettings(themePreference: preference));
        final settings = await repository.load();
        expect(settings.themePreference, preference);
      }
    });

    test('falls back to light for unknown stored values', () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.appThemePreference: 'future_theme',
      });
      final repository = SharedPrefsAppAppearanceSettingsRepository();

      final settings = await repository.load();

      expect(settings.themePreference, AppThemePreference.light);
    });
  });

  group('AppAppearanceController', () {
    test('updates state and persists the selected preference', () async {
      final repository = _FakeAppAppearanceSettingsRepository(
        settings: AppAppearanceSettings.defaults(),
      );
      final container = ProviderContainer(
        overrides: [
          appAppearanceSettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appAppearanceControllerProvider.future);
      await container
          .read(appAppearanceControllerProvider.notifier)
          .setThemePreference(AppThemePreference.dark);

      expect(
        container.read(appAppearanceControllerProvider).value!.themePreference,
        AppThemePreference.dark,
      );
      expect(repository.savedSettings.single.themePreference, AppThemePreference.dark);
    });

    test('same preference is a no-op', () async {
      final repository = _FakeAppAppearanceSettingsRepository(
        settings: AppAppearanceSettings.defaults(),
      );
      final container = ProviderContainer(
        overrides: [
          appAppearanceSettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appAppearanceControllerProvider.future);
      await container
          .read(appAppearanceControllerProvider.notifier)
          .setThemePreference(AppThemePreference.light);

      expect(repository.savedSettings, isEmpty);
    });

    test('save failure rolls back state and rethrows', () async {
      final repository = _FakeAppAppearanceSettingsRepository(
        settings: AppAppearanceSettings.defaults(),
        failOnSave: true,
      );
      final container = ProviderContainer(
        overrides: [
          appAppearanceSettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appAppearanceControllerProvider.future);

      await expectLater(
        container
            .read(appAppearanceControllerProvider.notifier)
            .setThemePreference(AppThemePreference.dark),
        throwsStateError,
      );
      expect(
        container.read(appAppearanceControllerProvider).value!.themePreference,
        AppThemePreference.light,
      );
    });
  });
}

class _FakeAppAppearanceSettingsRepository
    implements AppAppearanceSettingsRepository {
  _FakeAppAppearanceSettingsRepository({
    required AppAppearanceSettings settings,
    this.failOnSave = false,
  }) : _settings = settings;

  AppAppearanceSettings _settings;
  final bool failOnSave;
  final savedSettings = <AppAppearanceSettings>[];

  @override
  Future<AppAppearanceSettings> load() async {
    return _settings;
  }

  @override
  Future<void> save(AppAppearanceSettings settings) async {
    if (failOnSave) {
      throw StateError('save failed');
    }
    savedSettings.add(settings);
    _settings = settings;
  }
}
