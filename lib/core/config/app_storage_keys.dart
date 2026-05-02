/// Shared storage keys used across features.
///
/// Keeping keys in one place avoids string duplication and accidental drift
/// between settings module and feature modules.
abstract final class AppStorageKeys {
  static const String comicCacheDirectory = 'comic_cache_dir';
}

