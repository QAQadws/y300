/// Reproducible session projection extracted from forum responses.
final class ForumSessionSnapshot {
  /// Creates a session projection.
  const ForumSessionSnapshot({
    required this.isLoggedIn,
    required this.userId,
    required this.username,
    required this.formhash,
    required this.updatedAt,
    required this.source,
  });

  /// Whether the response proved an authenticated identity.
  final bool isLoggedIn;

  /// Discuz user identity, or an empty string when unknown.
  final String userId;

  /// Display name, or an empty string when unknown.
  final String username;

  /// Most recently extracted formhash, or an empty string.
  final String formhash;

  /// Time at which this projection was extracted.
  final DateTime updatedAt;

  /// Safe source label describing the extraction point.
  final String source;
}

/// Store for reproducible session and formhash projections.
abstract interface class ForumSessionStore {
  /// Returns the current projection synchronously when available.
  ForumSessionSnapshot? readCurrent();

  /// Returns a non-expired formhash when available.
  String? readFreshFormhash();

  /// Conservatively merges a newly extracted projection.
  Future<void> merge(ForumSessionSnapshot snapshot);

  /// Removes the current projection without modifying Cookies.
  Future<void> clear();
}

/// In-memory session projection used by the standard third-party builder.
final class MemoryForumSessionStore implements ForumSessionStore {
  /// Creates an ephemeral session store.
  MemoryForumSessionStore({
    this.formhashTtl = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Maximum age accepted by [readFreshFormhash].
  final Duration formhashTtl;
  final DateTime Function() _now;
  ForumSessionSnapshot? _current;
  @override
  ForumSessionSnapshot? readCurrent() => _current;
  @override
  String? readFreshFormhash() {
    final value = _current;
    if (value == null || value.formhash.trim().isEmpty) return null;
    final age = _now().difference(value.updatedAt);
    return age.isNegative || age <= formhashTtl ? value.formhash : null;
  }

  @override
  Future<void> merge(ForumSessionSnapshot snapshot) async {
    final current = _current;
    if (current == null) {
      _current = snapshot;
      return;
    }
    _current = ForumSessionSnapshot(
      isLoggedIn: snapshot.userId.trim().isNotEmpty
          ? snapshot.isLoggedIn
          : current.isLoggedIn,
      userId: snapshot.userId.trim().isNotEmpty
          ? snapshot.userId
          : current.userId,
      username: snapshot.username.trim().isNotEmpty
          ? snapshot.username
          : current.username,
      formhash: snapshot.formhash.trim().isNotEmpty
          ? snapshot.formhash
          : current.formhash,
      updatedAt: snapshot.updatedAt,
      source: snapshot.source,
    );
  }

  @override
  Future<void> clear() async => _current = null;
}
