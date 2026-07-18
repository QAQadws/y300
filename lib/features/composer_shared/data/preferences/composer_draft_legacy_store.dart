import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ComposerDraftLegacyStore {
  Future<Map<String, String>> loadEntries();

  Future<void> remove(String key);
}

class SharedPreferencesComposerDraftLegacyStore
    implements ComposerDraftLegacyStore {
  SharedPreferencesComposerDraftLegacyStore({
    SharedPreferences? sharedPreferences,
  }) : _sharedPreferences = sharedPreferences;

  static const String draftKeyPrefix = 'reply_draft.';

  final SharedPreferences? _sharedPreferences;

  @override
  Future<Map<String, String>> loadEntries() async {
    final preferences = await _preferences();
    return <String, String>{
      for (final key in preferences.getKeys())
        if (key.startsWith(draftKeyPrefix) &&
            preferences.getString(key) != null)
          key: preferences.getString(key)!,
    };
  }

  @override
  Future<void> remove(String key) async {
    await (await _preferences()).remove(key);
  }

  Future<SharedPreferences> _preferences() async {
    return _sharedPreferences ?? SharedPreferences.getInstance();
  }
}
