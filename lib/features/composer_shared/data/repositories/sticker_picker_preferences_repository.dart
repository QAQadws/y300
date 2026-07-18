import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

abstract class StickerPickerPreferencesRepository {
  Future<String?> loadLastGroupId();

  Future<void> saveLastGroupId(String groupId);
}

class SharedPreferencesStickerPickerPreferencesRepository
    implements StickerPickerPreferencesRepository {
  SharedPreferencesStickerPickerPreferencesRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<String?> loadLastGroupId() async {
    final raw = (await _preferencesStore.read(
      PreferenceKeys.replyStickerLastGroupId,
    ))?.trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  @override
  Future<void> saveLastGroupId(String groupId) async {
    final normalized = groupId.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _preferencesStore.write(
      PreferenceKeys.replyStickerLastGroupId,
      normalized,
    );
  }
}
