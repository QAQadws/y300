import 'forum_session_store.dart';

import '../network/forum_transport.dart';

sealed class ForumFormhashResult {
  const ForumFormhashResult();
}

final class ForumFormhashSuccess extends ForumFormhashResult {
  const ForumFormhashSuccess(this.value);
  final String value;
}

final class ForumFormhashError extends ForumFormhashResult {
  const ForumFormhashError(this.failure);
  final ForumTransportFailure failure;
}

abstract interface class ForumFormhashProvider {
  Future<ForumFormhashResult> loadFormhash({bool preferProfile = true});
}

final class SessionForumFormhashProvider implements ForumFormhashProvider {
  SessionForumFormhashProvider({
    required this.sessions,
    required this.loadFromProfile,
    required this.loadFallback,
  });
  final ForumSessionStore sessions;
  final Future<ForumFormhashResult> Function() loadFromProfile;
  final Future<ForumFormhashResult> Function() loadFallback;
  @override
  Future<ForumFormhashResult> loadFormhash({bool preferProfile = true}) async {
    final cached = sessions.readFreshFormhash();
    if (cached != null && cached.trim().isNotEmpty) {
      return ForumFormhashSuccess(cached);
    }
    final first = preferProfile ? loadFromProfile : loadFallback;
    final second = preferProfile ? loadFallback : loadFromProfile;
    ForumTransportFailure? lastFailure;
    for (final loader in <Future<ForumFormhashResult> Function()>[
      first,
      second,
    ]) {
      final result = await loader();
      if (result case ForumFormhashSuccess(:final value)) {
        final normalized = value.trim();
        if (normalized.isNotEmpty) return ForumFormhashSuccess(normalized);
      } else if (result case ForumFormhashError(:final failure)) {
        lastFailure = failure;
      }
    }
    return ForumFormhashError(
      lastFailure ??
          const ForumTransportFailure(
            kind: ForumTransportFailureKind.business,
            code: 'formhash_unavailable',
          ),
    );
  }
}
