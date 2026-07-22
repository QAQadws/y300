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

  Future<int> getCacheMaxBytes();

  Future<void> setCacheMaxBytes(int bytes);
}

class DataStorageSettingsRepositoryImpl
    implements DataStorageSettingsRepository {
  DataStorageSettingsRepositoryImpl({
    required StorageLocationRepository storageLocationRepository,
    PreferencesStore? preferencesStore,
  }) : _storageLocationRepository = storageLocationRepository,
       _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  static const int minCacheMaxBytes = 128 * 1024 * 1024;
  static const int defaultCacheMaxBytes = 512 * 1024 * 1024;
  static const int maxCacheMaxBytes = 2048 * 1024 * 1024;

  @Deprecated('Use minCacheMaxBytes.')
  static const int minImageCacheMaxBytes = minCacheMaxBytes;
  @Deprecated('Use defaultCacheMaxBytes.')
  static const int defaultImageCacheMaxBytes = defaultCacheMaxBytes;
  @Deprecated('Use maxCacheMaxBytes.')
  static const int maxImageCacheMaxBytes = maxCacheMaxBytes;

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
  Future<int> getCacheMaxBytes() async {
    final current = await _preferencesStore.read(
      PreferenceKeys.cacheMaxBytesV1,
    );
    if (current != null) {
      return _normalizeCacheMaxBytes(current);
    }
    final legacy = await _preferencesStore.read(
      PreferenceKeys.imageCacheMaxBytes,
    );
    if (legacy == null) {
      return defaultCacheMaxBytes;
    }
    final migrated = legacy <= 0
        ? defaultCacheMaxBytes
        : _normalizeCacheMaxBytes(legacy);
    await _preferencesStore.write(PreferenceKeys.cacheMaxBytesV1, migrated);
    return migrated;
  }

  @override
  Future<void> setCacheMaxBytes(int bytes) async {
    await _preferencesStore.write(
      PreferenceKeys.cacheMaxBytesV1,
      _normalizeCacheMaxBytes(bytes),
    );
  }

  int _normalizeCacheMaxBytes(int bytes) {
    return bytes.clamp(minCacheMaxBytes, maxCacheMaxBytes).toInt();
  }
}
