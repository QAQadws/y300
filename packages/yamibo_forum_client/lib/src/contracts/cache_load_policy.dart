/// Cache read policies shared by source-neutral repositories.
library;

/// Values describing cache load policy.
enum CacheLoadPolicy {
  /// Cache first.
  cacheFirst,

  /// Network first.
  networkFirst,
}
