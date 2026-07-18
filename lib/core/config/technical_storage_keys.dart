/// Storage keys for runtime state that is not a user personalization domain.
///
/// These values intentionally stay outside `PreferenceKeys`. Ordinary
/// personalization resets must not clear authentication state or request
/// governance checkpoints.
abstract final class TechnicalStorageKeys {
  static const String networkCookiesV1 = 'network.cookies.v1';
  static const String searchLastSearchAtMs = 'search.last_search_at_ms';
}
