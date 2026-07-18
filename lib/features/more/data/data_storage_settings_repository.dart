import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';

/// Settings facade for "More > Data and storage".
///
/// The repository owns user preferences and directory picking, while concrete
/// directory creation remains in [DownloadStorageService].  This keeps the More
/// feature from knowing the download storage folder layout.
abstract class DataStorageSettingsRepository {
  Future<String> getDefaultStoragePath();

  Future<String?> getCustomStoragePath();

  Future<void> setCustomStoragePath(String? path);

  Future<String?> pickDirectory();

  Future<int> getImageCacheMaxBytes();

  Future<void> setImageCacheMaxBytes(int bytes);
}

class DataStorageSettingsRepositoryImpl
    implements DataStorageSettingsRepository {
  DataStorageSettingsRepositoryImpl({
    required StorageLocationRepository storageLocationRepository,
    PreferencesStore? preferencesStore,
  }) : _storageLocationRepository = storageLocationRepository,
       _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  static const int minImageCacheMaxBytes = 128 * 1024 * 1024;
  static const int defaultImageCacheMaxBytes = 512 * 1024 * 1024;
  static const int maxImageCacheMaxBytes = 2048 * 1024 * 1024;

  final StorageLocationRepository _storageLocationRepository;
  final PreferencesStore _preferencesStore;

  @override
  Future<String> getDefaultStoragePath() {
    return _storageLocationRepository.getDefaultStorageRoot();
  }

  @override
  Future<String?> getCustomStoragePath() {
    return _storageLocationRepository.getCustomStorageRoot();
  }

  @override
  Future<void> setCustomStoragePath(String? path) {
    return _storageLocationRepository.setCustomStorageRoot(path);
  }

  @override
  Future<String?> pickDirectory() {
    return _storageLocationRepository.pickDirectory();
  }

  @override
  Future<int> getImageCacheMaxBytes() async {
    final value = await _preferencesStore.read(
      PreferenceKeys.imageCacheMaxBytes,
    );
    if (value == null || value <= 0) {
      return defaultImageCacheMaxBytes;
    }
    return _normalizeImageCacheMaxBytes(value);
  }

  @override
  Future<void> setImageCacheMaxBytes(int bytes) async {
    await _preferencesStore.write(
      PreferenceKeys.imageCacheMaxBytes,
      _normalizeImageCacheMaxBytes(bytes),
    );
  }

  int _normalizeImageCacheMaxBytes(int bytes) {
    return bytes.clamp(minImageCacheMaxBytes, maxImageCacheMaxBytes).toInt();
  }
}
