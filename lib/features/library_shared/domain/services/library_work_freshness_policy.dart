/// Freshness policy for library source metadata checks.
///
/// `lastCheckedAt` records that the app attempted to check the source, while
/// `lastFetchedAt` records that source data was actually refreshed. Keeping the
/// policy small makes comic/novel adapters share one throttling rule without
/// moving repository-specific refresh logic into the shared UI.
class LibraryWorkFreshnessPolicy {
  const LibraryWorkFreshnessPolicy({required this.checkInterval});

  const LibraryWorkFreshnessPolicy.detailDefaults()
    : checkInterval = const Duration(hours: 24);

  final Duration checkInterval;

  bool shouldCheck({required DateTime? lastCheckedAt, required DateTime now}) {
    if (lastCheckedAt == null) {
      return true;
    }
    if (lastCheckedAt.isAfter(now)) {
      return false;
    }
    return now.difference(lastCheckedAt) >= checkInterval;
  }
}
