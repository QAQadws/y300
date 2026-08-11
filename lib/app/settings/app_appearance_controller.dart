import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/settings/app_appearance_settings_repository.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/preferences/preferences_providers.dart';

final appAppearanceSettingsRepositoryProvider =
    Provider<AppAppearanceSettingsRepository>((ref) {
      return SharedPrefsAppAppearanceSettingsRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final appAppearanceControllerProvider =
    AsyncNotifierProvider<AppAppearanceController, AppAppearanceSettings>(
      AppAppearanceController.new,
    );

class AppAppearanceController extends AsyncNotifier<AppAppearanceSettings> {
  AppAppearanceSettingsRepository get _repository =>
      ref.read(appAppearanceSettingsRepositoryProvider);

  @override
  Future<AppAppearanceSettings> build() {
    return _repository.load();
  }

  Future<void> setThemeFamily(AppThemeFamily family) async {
    final previous = state.value ?? AppAppearanceSettings.defaults();
    if (previous.themeFamily == family) {
      return;
    }

    final next = previous.copyWith(themeFamily: family);
    await _saveOrRollback(previous, next);
  }

  Future<void> setBrightnessPreference(
    AppBrightnessPreference preference,
  ) async {
    final previous = state.value ?? AppAppearanceSettings.defaults();
    if (previous.brightnessPreference == preference) {
      return;
    }

    final next = previous.copyWith(brightnessPreference: preference);
    await _saveOrRollback(previous, next);
  }

  Future<void> _saveOrRollback(
    AppAppearanceSettings previous,
    AppAppearanceSettings next,
  ) async {
    state = AsyncData(next);
    try {
      await _repository.save(next);
    } catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncData(previous);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setLanguagePreference(AppLanguage preference) async {
    final previous = state.value ?? AppAppearanceSettings.defaults();
    if (previous.languagePreference == preference) {
      return;
    }

    final next = previous.copyWith(languagePreference: preference);
    await _saveOrRollback(previous, next);
  }
}
