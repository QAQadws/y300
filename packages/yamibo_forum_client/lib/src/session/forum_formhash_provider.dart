import 'forum_session_store.dart';

import '../network/forum_request.dart';
import '../network/forum_transport.dart';

/// Result of attempting to obtain a Discuz formhash.
sealed class ForumFormhashResult {
  const ForumFormhashResult();
}

/// Successful formhash lookup.
final class ForumFormhashSuccess extends ForumFormhashResult {
  /// Creates a successful result containing [value].
  const ForumFormhashSuccess(this.value);

  /// Non-empty Discuz formhash.
  final String value;
}

/// Failed formhash lookup with a transport-neutral failure.
final class ForumFormhashError extends ForumFormhashResult {
  /// Creates a failed lookup.
  const ForumFormhashError(this.failure);

  /// Safe failure returned by the attempted sources.
  final ForumTransportFailure failure;
}

/// Override point for hosts that already manage formhash acquisition.
abstract interface class ForumFormhashProvider {
  /// Loads a usable formhash, optionally preferring the profile endpoint.
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  });
}

/// Formhash provider backed by a session projection and two source loaders.
final class SessionForumFormhashProvider implements ForumFormhashProvider {
  /// Creates a provider with profile and fallback loaders.
  SessionForumFormhashProvider({
    required this.sessions,
    required this.loadFromProfile,
    required this.loadFallback,
  });

  /// Session projection checked before network loaders.
  final ForumSessionStore sessions;

  /// Preferred profile formhash loader.
  final Future<ForumFormhashResult> Function(
    ForumRequestCancellation? cancellation,
  )
  loadFromProfile;

  /// Fallback forum-index formhash loader.
  final Future<ForumFormhashResult> Function(
    ForumRequestCancellation? cancellation,
  )
  loadFallback;
  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return const ForumFormhashError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.cancelled,
          code: 'request_cancelled',
        ),
      );
    }
    final cached = sessions.readFreshFormhash();
    if (cached != null && cached.trim().isNotEmpty) {
      return ForumFormhashSuccess(cached);
    }
    final first = preferProfile ? loadFromProfile : loadFallback;
    final second = preferProfile ? loadFallback : loadFromProfile;
    ForumTransportFailure? lastFailure;
    for (final loader
        in <Future<ForumFormhashResult> Function(ForumRequestCancellation?)>[
          first,
          second,
        ]) {
      if (cancellation?.isCancelled ?? false) {
        return const ForumFormhashError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.cancelled,
            code: 'request_cancelled',
          ),
        );
      }
      final result = await loader(cancellation);
      if (cancellation?.isCancelled ?? false) {
        return const ForumFormhashError(
          ForumTransportFailure(
            kind: ForumTransportFailureKind.cancelled,
            code: 'request_cancelled',
          ),
        );
      }
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
