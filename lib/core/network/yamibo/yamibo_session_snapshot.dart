class YamiboSessionSnapshot {
  const YamiboSessionSnapshot({
    required this.isLoggedIn,
    required this.uid,
    required this.username,
    required this.formhash,
    required this.updatedAt,
    required this.source,
  });

  final bool isLoggedIn;
  final String uid;
  final String username;
  final String formhash;
  final DateTime updatedAt;
  final String source;

  YamiboSessionSnapshot copyWith({
    bool? isLoggedIn,
    String? uid,
    String? username,
    String? formhash,
    DateTime? updatedAt,
    String? source,
  }) {
    return YamiboSessionSnapshot(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      uid: uid ?? this.uid,
      username: username ?? this.username,
      formhash: formhash ?? this.formhash,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
    );
  }
}
