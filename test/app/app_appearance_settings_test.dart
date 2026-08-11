import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/settings/app_appearance_settings_repository.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/core/preferences/preference_key_names.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsAppAppearanceSettingsRepository', () {
    test(
      'defaults to warm paper and light when no preference is stored',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = SharedPrefsAppAppearanceSettingsRepository();

        final settings = await repository.load();

        expect(settings.themeFamily, AppThemeFamily.warmPaper);
        expect(settings.brightnessPreference, AppBrightnessPreference.light);
        expect(settings.languagePreference, AppLanguage.system);
      },
    );

    test(
      'saves and loads all theme families and brightness preferences',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = SharedPrefsAppAppearanceSettingsRepository();

        for (final family in AppThemeFamily.values) {
          for (final preference in AppBrightnessPreference.values) {
            await repository.save(
              AppAppearanceSettings(
                themeFamily: family,
                brightnessPreference: preference,
                languagePreference: AppLanguage.system,
              ),
            );
            final settings = await repository.load();
            expect(settings.themeFamily, family);
            expect(settings.brightnessPreference, preference);
          }
        }
      },
    );

    test('saves and loads all app language preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPrefsAppAppearanceSettingsRepository();

      for (final language in AppLanguage.values) {
        await repository.save(
          AppAppearanceSettings(
            brightnessPreference: AppBrightnessPreference.light,
            languagePreference: language,
          ),
        );
        final settings = await repository.load();
        expect(settings.languagePreference, language);
      }
    });

    test(
      'falls back to warm paper and light for unknown stored values',
      () async {
        SharedPreferences.setMockInitialValues({
          PreferenceKeyNames.appThemeFamily: 'future_family',
          AppStorageKeys.appThemePreference: 'future_theme',
        });
        final repository = SharedPrefsAppAppearanceSettingsRepository();

        final settings = await repository.load();

        expect(settings.themeFamily, AppThemeFamily.warmPaper);
        expect(settings.brightnessPreference, AppBrightnessPreference.light);
      },
    );

    test('falls back to system language for unknown stored value', () async {
      SharedPreferences.setMockInitialValues({
        PreferenceKeyNames.appLanguagePreference: 'future_language',
      });
      final repository = SharedPrefsAppAppearanceSettingsRepository();

      final settings = await repository.load();

      expect(settings.languagePreference, AppLanguage.system);
    });
  });

  group('AppAppearanceController', () {
    test(
      'updates state and persists family and brightness independently',
      () async {
        final repository = _FakeAppAppearanceSettingsRepository(
          settings: AppAppearanceSettings.defaults(),
        );
        final container = ProviderContainer(
          overrides: [
            appAppearanceSettingsRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(appAppearanceControllerProvider.future);
        await container
            .read(appAppearanceControllerProvider.notifier)
            .setThemeFamily(AppThemeFamily.moonWhite);
        await container
            .read(appAppearanceControllerProvider.notifier)
            .setBrightnessPreference(AppBrightnessPreference.dark);

        expect(
          container.read(appAppearanceControllerProvider).value!.themeFamily,
          AppThemeFamily.moonWhite,
        );
        expect(
          container
              .read(appAppearanceControllerProvider)
              .value!
              .brightnessPreference,
          AppBrightnessPreference.dark,
        );
        expect(repository.savedSettings, hasLength(2));
        expect(
          repository.savedSettings.last.themeFamily,
          AppThemeFamily.moonWhite,
        );
        expect(
          repository.savedSettings.last.brightnessPreference,
          AppBrightnessPreference.dark,
        );
      },
    );

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
          .setBrightnessPreference(AppBrightnessPreference.light);

      expect(repository.savedSettings, isEmpty);
    });

    test('updates language state and persists the selected language', () async {
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
          .setLanguagePreference(AppLanguage.traditionalChinese);

      expect(
        container
            .read(appAppearanceControllerProvider)
            .value!
            .languagePreference,
        AppLanguage.traditionalChinese,
      );
      expect(
        repository.savedSettings.single.languagePreference,
        AppLanguage.traditionalChinese,
      );
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
            .setThemeFamily(AppThemeFamily.moonWhite),
        throwsStateError,
      );
      expect(
        container.read(appAppearanceControllerProvider).value!.themeFamily,
        AppThemeFamily.warmPaper,
      );
    });

    test('language save failure rolls back state and rethrows', () async {
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
            .setLanguagePreference(AppLanguage.traditionalChinese),
        throwsStateError,
      );
      expect(
        container
            .read(appAppearanceControllerProvider)
            .value!
            .languagePreference,
        AppLanguage.system,
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
