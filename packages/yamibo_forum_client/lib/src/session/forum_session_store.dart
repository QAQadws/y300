final class ForumSessionSnapshot {
  const ForumSessionSnapshot({
    required this.isLoggedIn,
    required this.userId,
    required this.username,
    required this.formhash,
    required this.updatedAt,
    required this.source,
  });
  final bool isLoggedIn;
  final String userId;
  final String username;
  final String formhash;
  final DateTime updatedAt;
  final String source;
}

abstract interface class ForumSessionStore {
  ForumSessionSnapshot? readCurrent();
  String? readFreshFormhash();
  Future<void> merge(ForumSessionSnapshot snapshot);
  Future<void> clear();
}

final class MemoryForumSessionStore implements ForumSessionStore {
  MemoryForumSessionStore({
    this.formhashTtl = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
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
