/// Access inputs that may change whether a remote image can be retrieved.
typedef ImageCacheFailureIdentity = ({
  String cacheKey,
  String sourceUrl,
  String? referer,
});

/// Short-lived, bounded memory of confirmed missing resources. No timer,
/// response payload, file, or persistent cache record is retained.
final class ImageCacheFailureBackoff {
  ImageCacheFailureBackoff({
    this.cooldown = const Duration(seconds: 30),
    this.maxEntries = 256,
    DateTime Function()? now,
  }) : assert(!cooldown.isNegative),
       assert(maxEntries >= 0),
       _now = now ?? DateTime.now;

  final Duration cooldown;
  final int maxEntries;
  final DateTime Function() _now;
  final _missingSince = <ImageCacheFailureIdentity, DateTime>{};

  bool contains(ImageCacheFailureIdentity identity) {
    final failedAt = _missingSince.remove(identity);
    if (failedAt == null) return false;
    final age = _now().difference(failedAt);
    if (age.isNegative || age >= cooldown) return false;
    // A hit promotes the entry without extending its original deadline.
    _missingSince[identity] = failedAt;
    return true;
  }

  void remember(ImageCacheFailureIdentity identity) {
    if (maxEntries == 0 || cooldown == Duration.zero) return;
    _missingSince.remove(identity);
    while (_missingSince.length >= maxEntries) {
      _missingSince.remove(_missingSince.keys.first);
    }
    _missingSince[identity] = _now();
  }

  void remove(ImageCacheFailureIdentity identity) =>
      _missingSince.remove(identity);

  void clear() => _missingSince.clear();
}
