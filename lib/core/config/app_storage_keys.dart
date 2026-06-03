/// Shared storage keys used across features.
///
/// Keeping keys in one place avoids string duplication and accidental drift
/// between settings module and feature modules.
abstract final class AppStorageKeys {
  static const String legacyComicCacheDirectory = 'comic_cache_dir';
  static const String comicCacheDirectory = legacyComicCacheDirectory;
  static const String imageCacheMaxBytes = 'image_cache_max_bytes';
  static const String imageCacheCustomDirectory = 'image_cache_custom_dir';
  static const String downloadStorageDirectory = 'download_storage_dir';
  static const String forumShellMode = 'forum_shell_mode';
}
