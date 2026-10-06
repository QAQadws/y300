/// Storage keys for runtime state that is not a user personalization domain.
///
/// These values intentionally stay outside `PreferenceKeys`. Ordinary
/// personalization resets must not clear authentication state or request
/// governance checkpoints.
abstract final class TechnicalStorageKeys {
  static const String accountDisplayUidV1Prefix = 'profile.display_uid.v1.';
  static const String networkCookiesV1 = 'network.cookies.v1';
  static const String forumHomeCacheOwnerV1 = 'forum.home_cache_owner.v1';
  static const String forumHomeStartupSnapshotV1 =
      'forum.home_startup_snapshot.v1';
  static const String forumHomeCarouselLayoutV1 =
      'forum.home_carousel_layout.v1';
  static const String searchLastSearchAtMs = 'search.last_search_at_ms';
  static const String downloadStorageRootMigrationV1 =
      'storage.download_root_migration.v1';
  static const String dailySignInAttemptV1Prefix =
      'profile.daily_sign_in.attempt.v1.';
}
