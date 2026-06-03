import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';

abstract class ForumModeSettingsRepository {
  Future<ForumShellMode> loadMode();

  Future<void> saveMode(ForumShellMode mode);
}

class SharedPrefsForumModeSettingsRepository
    implements ForumModeSettingsRepository {
  @override
  Future<ForumShellMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseMode(prefs.getString(AppStorageKeys.forumShellMode));
  }

  @override
  Future<void> saveMode(ForumShellMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppStorageKeys.forumShellMode, mode.name);
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
