import 'forum_session_store.dart';

abstract interface class ForumFormhashProvider {
  Future<String> loadFormhash({bool preferProfile = true});
}

final class SessionForumFormhashProvider implements ForumFormhashProvider {
  SessionForumFormhashProvider({
    required this.sessions,
    required this.loadFromProfile,
    required this.loadFallback,
  });
  final ForumSessionStore sessions;
  final Future<String> Function() loadFromProfile;
  final Future<String> Function() loadFallback;
  @override
  Future<String> loadFormhash({bool preferProfile = true}) async {
    final cached = sessions.readFreshFormhash();
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final first = preferProfile ? loadFromProfile : loadFallback;
    final second = preferProfile ? loadFallback : loadFromProfile;
    for (final loader in <Future<String> Function()>[first, second]) {
      final value = (await loader()).trim();
      if (value.isNotEmpty) return value;
    }
    throw StateError('formhash_unavailable');
  }
}
