import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data access abstraction for "More > Cache settings".
///
/// Keeping platform/file APIs here avoids coupling presentation with
/// plugin-specific details.
abstract class MoreSettingsRepository {
  Future<String> getDefaultCacheDirectory();

  Future<String?> getCustomCacheDirectory();

  Future<void> setCustomCacheDirectory(String? path);

  Future<String?> pickDirectory();
}

class MoreSettingsRepositoryImpl implements MoreSettingsRepository {
  static const String _customCacheDirectoryKey = 'comic_cache_dir';

  @override
  Future<String> getDefaultCacheDirectory() async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  @override
  Future<String?> getCustomCacheDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_customCacheDirectoryKey)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> setCustomCacheDirectory(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      await prefs.remove(_customCacheDirectoryKey);
      return;
    }
    await prefs.setString(_customCacheDirectoryKey, normalized);
  }

  @override
  Future<String?> pickDirectory() {
    return FilePicker.getDirectoryPath();
  }
}

