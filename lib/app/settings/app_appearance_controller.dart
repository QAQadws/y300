import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/settings/app_appearance_settings_repository.dart';
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

  Future<void> setThemePreference(AppThemePreference preference) async {
    final previous = state.value ?? AppAppearanceSettings.defaults();
    if (previous.themePreference == preference) {
      return;
    }

    final next = previous.copyWith(themePreference: preference);
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
}
