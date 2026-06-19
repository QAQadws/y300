import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';

class YamiboSessionStore {
  YamiboSessionStore({
    this.formhashTtl = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration formhashTtl;
  final DateTime Function() _now;
  YamiboSessionSnapshot? _current;

  YamiboSessionSnapshot? readCurrent() => _current;

  String? readFreshFormhash() {
    final current = _current;
    if (current == null || current.formhash.trim().isEmpty) {
      return null;
    }
    final age = _now().difference(current.updatedAt);
    if (age.isNegative || age <= formhashTtl) {
      return current.formhash;
    }
    return null;
  }

  YamiboSessionSnapshot? saveExtracted(YamiboSessionSnapshot extracted) {
    final current = _current;
    final next = current == null ? extracted : _merge(current, extracted);
    _current = next;
    return next;
  }

  void clear() {
    _current = null;
  }

  YamiboSessionSnapshot _merge(
    YamiboSessionSnapshot current,
    YamiboSessionSnapshot extracted,
  ) {
    final extractedFormhash = extracted.formhash.trim();
    final extractedUid = extracted.uid.trim();
    final extractedUsername = extracted.username.trim();
    final hasExplicitUid = extractedUid.isNotEmpty;
    final isLoggedIn = hasExplicitUid
        ? extracted.isLoggedIn
        : extractedUsername.isNotEmpty
        ? true
        : current.isLoggedIn;
    return YamiboSessionSnapshot(
      isLoggedIn: isLoggedIn,
      uid: extractedUid.isNotEmpty ? extractedUid : current.uid,
      username: hasExplicitUid && !extracted.isLoggedIn
          ? ''
          : extractedUsername.isNotEmpty
          ? extractedUsername
          : current.username,
      formhash: extractedFormhash.isNotEmpty
          ? extractedFormhash
          : current.formhash,
      updatedAt: extracted.updatedAt,
      source: extracted.source,
    );
  }
}
