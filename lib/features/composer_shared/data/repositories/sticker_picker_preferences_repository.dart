import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

abstract class StickerPickerPreferencesRepository {
  Future<String?> loadLastGroupId();

  Future<void> saveLastGroupId(String groupId);
}

class SharedPreferencesStickerPickerPreferencesRepository
    implements StickerPickerPreferencesRepository {
  SharedPreferencesStickerPickerPreferencesRepository({
    SharedPreferences? sharedPreferences,
  }) : _sharedPreferences = sharedPreferences;

  final SharedPreferences? _sharedPreferences;

  @override
  Future<String?> loadLastGroupId() async {
    final raw = (await _prefs())
        .getString(AppStorageKeys.replyStickerLastGroupId)
        ?.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  @override
  Future<void> saveLastGroupId(String groupId) async {
    final normalized = groupId.trim();
    if (normalized.isEmpty) {
      return;
    }
    await (await _prefs()).setString(
      AppStorageKeys.replyStickerLastGroupId,
      normalized,
    );
  }

  Future<SharedPreferences> _prefs() async {
    final sharedPreferences = _sharedPreferences;
    if (sharedPreferences != null) {
      return sharedPreferences;
    }
    return SharedPreferences.getInstance();
  }
}
