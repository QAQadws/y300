import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';

abstract class ForumModeSettingsRepository {
  Future<ForumShellMode> loadMode();

  Future<void> saveMode(ForumShellMode mode);
}

class SharedPrefsForumModeSettingsRepository
    implements ForumModeSettingsRepository {
  SharedPrefsForumModeSettingsRepository({PreferencesStore? preferencesStore})
    : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<ForumShellMode> loadMode() async {
    return _parseMode(
      await _preferencesStore.read(PreferenceKeys.forumShellMode),
    );
  }

  @override
  Future<void> saveMode(ForumShellMode mode) async {
    await _preferencesStore.write(PreferenceKeys.forumShellMode, mode.name);
  }

  ForumShellMode _parseMode(String? raw) {
    for (final mode in ForumShellMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return ForumShellMode.webview;
  }
}
