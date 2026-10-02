import '../contracts/thread_detail_models.dart';
import '../contracts/thread_repository.dart';
import '../session/forum_cookie_store.dart';
import '../session/forum_session_store.dart';

/// A process-local bridge between the HTML locator and its paired detail source.
/// It never writes the located response to the persistent document cache.
final class ThreadDetailHandoffCoordinator {
  /// Creates a bridge bound to one client composition and its session ports.
  ThreadDetailHandoffCoordinator({
    required this.siteOrigin,
    required this.cookies,
    required this.sessions,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Forum origin used to select the same Cookies as HTML requests.
  final Uri siteOrigin;

  /// Shared Cookie port, when supplied by the host.
  final ForumCookieStore? cookies;

  /// Shared session projection, when supplied by the host.
  final ForumSessionStore? sessions;
  final DateTime Function() _now;
  final Map<String, int> _generations = <String, int>{};
  Uri get _threadUri =>
      siteOrigin.replace(path: '/forum.php', queryParameters: const {});

  /// Rejects outstanding handoffs for a thread before cache invalidation.
  void invalidate(String tid) {
    _generations[tid] = (_generations[tid] ?? 0) + 1;
  }

  /// Captures the request boundary before a location request is sent.
  Future<ThreadDetailHandoffBoundary?> capture(String tid) async {
    final store = cookies;
    if (store == null) return null;
    try {
      return ThreadDetailHandoffBoundary(
        generation: _generations[tid] ?? 0,
        cookies: Map<String, String>.unmodifiable(await store.read(_threadUri)),
        identity: _identity(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Creates a one-use handoff only if the request boundary stayed stable.
  Future<ThreadDetailHandoff?> issue({
    required ThreadDetailHandoffBoundary? boundary,
    required String tid,
    required String pid,
    required int page,
    required ThreadDetailData detail,
  }) async {
    if (boundary == null ||
        boundary.generation != (_generations[tid] ?? 0) ||
        !_identityMatches(boundary.identity)) {
      return null;
    }
    try {
      final currentCookies = await cookies!.read(_threadUri);
      if (!_sameCookies(boundary.cookies, currentCookies) ||
          boundary.generation != (_generations[tid] ?? 0) ||
          !_identityMatches(boundary.identity)) {
        return null;
      }
      return _LocatedThreadDetail(
        owner: this,
        tid: tid,
        pid: pid,
        page: page,
        detail: detail,
        boundary: boundary,
        issuedAt: _now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the captured detail once, if its target and boundary still match.
  Future<ThreadDetailData?> consume(
    ThreadDetailHandoff handoff, {
    required String tid,
    required String pid,
    required int page,
    required ThreadDetailQuery query,
  }) async {
    if (handoff is! _LocatedThreadDetail ||
        !identical(handoff.owner, this) ||
        handoff.consumed) {
      return null;
    }
    handoff.consumed = true;
    final detail = handoff.detail;
    final boundary = handoff.boundary;
    // The route may outlive this first read. Drop large content and Cookie
    // evidence even when the handoff cannot be used.
    handoff.detail = null;
    handoff.boundary = null;
    final age = _now().difference(handoff.issuedAt);
    if (detail == null ||
        boundary == null ||
        age.isNegative ||
        age > const Duration(seconds: 60) ||
        !query.isEmpty ||
        handoff.tid != tid ||
        handoff.pid != pid ||
        handoff.page != page ||
        boundary.generation != (_generations[tid] ?? 0) ||
        !_identityMatches(boundary.identity)) {
      return null;
    }
    try {
      final currentCookies = await cookies!.read(_threadUri);
      if (!_sameCookies(boundary.cookies, currentCookies) ||
          boundary.generation != (_generations[tid] ?? 0) ||
          !_identityMatches(boundary.identity)) {
        return null;
      }
      return detail;
    } catch (_) {
      return null;
    }
  }

  (bool, String) _identity() {
    final current = sessions?.readCurrent();
    return (current?.isLoggedIn ?? false, current?.userId.trim() ?? '');
  }

  bool _identityMatches((bool, String) expected) => _identity() == expected;

  bool _sameCookies(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Request-time cache and session evidence used only for a pending handoff.
final class ThreadDetailHandoffBoundary {
  /// Creates an immutable request-boundary snapshot.
  const ThreadDetailHandoffBoundary({
    required this.generation,
    required this.cookies,
    required this.identity,
  });

  /// Thread cache generation at request start.
  final int generation;

  /// Applicable Cookies kept only for this short-lived in-memory comparison.
  final Map<String, String> cookies;

  /// Authenticated state and user ID at request start.
  final (bool, String) identity;
}

final class _LocatedThreadDetail implements ThreadDetailHandoff {
  _LocatedThreadDetail({
    required this.owner,
    required this.tid,
    required this.pid,
    required this.page,
    required this.detail,
    required this.boundary,
    required this.issuedAt,
  });

  final ThreadDetailHandoffCoordinator owner;
  final String tid;
  final String pid;
  final int page;
  ThreadDetailData? detail;
  ThreadDetailHandoffBoundary? boundary;
  final DateTime issuedAt;
  bool consumed = false;
}
