/// Shared storage keys used across features.
///
/// Keeping keys in one place avoids string duplication and accidental drift
/// between settings module and feature modules.
abstract final class AppStorageKeys {
  static const String comicCacheDirectory = 'comic_cache_dir';
  static const String imageCacheMaxBytes = 'image_cache_max_bytes';
  static const String downloadStorageDirectory = 'download_storage_dir';
}
