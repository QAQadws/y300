import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

/// Data access abstraction for "More > Cache settings".
///
/// Keeping platform/file APIs here avoids coupling presentation with
/// plugin-specific details.
abstract class MoreSettingsRepository {
  Future<String> getDefaultCacheDirectory();

  Future<String?> getCustomCacheDirectory();

  Future<void> setCustomCacheDirectory(String? path);

  Future<String?> pickDirectory();

  Future<int> getImageCacheMaxBytes();

  Future<void> setImageCacheMaxBytes(int bytes);
}

class MoreSettingsRepositoryImpl implements MoreSettingsRepository {
  static const int defaultImageCacheMaxBytes = 512 * 1024 * 1024;

  @override
  Future<String> getDefaultCacheDirectory() async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  @override
  Future<String?> getCustomCacheDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(AppStorageKeys.comicCacheDirectory)?.trim();
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
      await prefs.remove(AppStorageKeys.comicCacheDirectory);
      return;
    }
    await prefs.setString(AppStorageKeys.comicCacheDirectory, normalized);
  }

  @override
  Future<String?> pickDirectory() {
    return FilePicker.getDirectoryPath();
  }

  @override
  Future<int> getImageCacheMaxBytes() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(AppStorageKeys.imageCacheMaxBytes);
    if (value == null || value <= 0) {
      return defaultImageCacheMaxBytes;
    }
    return value;
  }

  @override
  Future<void> setImageCacheMaxBytes(int bytes) async {
    final normalized = bytes.clamp(
      128 * 1024 * 1024,
      2048 * 1024 * 1024,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppStorageKeys.imageCacheMaxBytes, normalized);
  }
}
