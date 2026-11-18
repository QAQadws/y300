/// Evidence accepted by the package WAF coordinator.
/// Values describing forum waf evidence.
enum ForumWafEvidence {
  /// Http status405.
  httpStatus405,

  /// ESA's automatic rate-limit challenge response header.
  httpAutoRatelimit,
}

/// Header-only access assessment; callers enforce the managed-site boundary.
enum ForumWafResponseDecision {
  /// No recognized edge denial.
  none,

  /// Existing status-based challenge.
  httpStatus405,

  /// A known edge rule for which browser recovery may be attempted.
  httpAutoRatelimit,

  /// An edge denial that must not launch automatic browser recovery.
  accessDenied;

  /// Only known recovery evidence can start the browser.
  ForumWafEvidence? get evidence => switch (this) {
    httpStatus405 => ForumWafEvidence.httpStatus405,
    httpAutoRatelimit => ForumWafEvidence.httpAutoRatelimit,
    none || accessDenied => null,
  };
}

/// Shared by ordinary requests, image streams, and native clearance probes.
/// Never inspects a response body or treats a vendor name as challenge proof.
abstract final class ForumWafResponsePolicy {
  /// Classifies status and headers without I/O or response payload data.
  static ForumWafResponseDecision classify({
    required int? statusCode,
    Map<String, List<String>> headers = const {},
  }) {
    if (statusCode == 405) return ForumWafResponseDecision.httpStatus405;
    var rateLimited = false;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'x-tengine-error') continue;
      for (final value in entry.value) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'denied by http_auto_ratelimit') {
          rateLimited = true;
        } else if (normalized == 'denied by' ||
            normalized.startsWith('denied by ')) {
          // Unknown or conflicting denials cannot prove a solvable challenge.
          return ForumWafResponseDecision.accessDenied;
        }
      }
    }
    return rateLimited
        ? ForumWafResponseDecision.httpAutoRatelimit
        : ForumWafResponseDecision.none;
  }
}

/// Result returned by a Host WAF recovery implementation.
enum ForumWafRecoveryResult {
  /// Verified.
  verified,

  /// Cancelled.
  cancelled,

  /// Unavailable.
  unavailable,

  /// Cooling down.
  coolingDown,

  /// Failed.
  failed,
}

/// Native probe outcome after a Host challenge attempt.
/// Values describing forum waf clearance.
enum ForumWafClearance {
  /// Cleared.
  cleared,

  /// Challenged.
  challenged,

  /// Inconclusive.
  inconclusive,
}

/// Synchronizes challenge Cookies into the native transport.
typedef ForumWafCookieSync = Future<void> Function(Uri uri);

/// Probes whether the native transport has obtained clearance.
typedef ForumWafClearanceProbe =
    Future<ForumWafClearance> Function({
      required Uri uri,
      required String userAgent,
    });

/// Verifies clearance after synchronizing Host challenge Cookies.
final class ForumWafVerificationService {
  /// Creates a verification service from Host synchronization and probe ports.
  const ForumWafVerificationService({
    required this._syncCookies,
    required this._probe,
  });

  final ForumWafCookieSync _syncCookies;
  final ForumWafClearanceProbe _probe;

  /// Synchronizes Cookies and runs the native clearance probe.
  Future<ForumWafClearance> verify({
    required Uri uri,
    required String userAgent,
  }) async {
    await _syncCookies(uri);
    return _probe(uri: uri, userAgent: userAgent);
  }
}

/// Safe challenge description passed to the Host recovery delegate.
final class ForumWafRecoveryRequest {
  /// Creates a recovery request.
  const ForumWafRecoveryRequest({
    required this.uri,
    required this.method,
    required this.evidence,
    required this.userAgent,
  });

  /// Challenged same-site URI without response payload data.
  final Uri uri;

  /// HTTP method of the challenged request.
  final String method;

  /// Proven challenge evidence.
  final ForumWafEvidence evidence;

  /// Request identity the Host challenge browser must reuse.
  final String userAgent;
}

/// Platform boundary responsible for executing and verifying a WAF challenge.
abstract interface class ForumWafRecoveryDelegate {
  /// Attempts one fail-closed recovery transaction.
  Future<ForumWafRecoveryResult> recover(ForumWafRecoveryRequest request);
}

/// Single-flight WAF recovery coordinator with a bounded cooldown.
final class ForumWafCoordinator implements ForumWafRecoveryDelegate {
  /// Creates a coordinator; a Host launcher must later be attached.
  ForumWafCoordinator({
    this.cooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Minimum delay between completed recovery attempts.
  final Duration cooldown;
  final DateTime Function() _now;
  Future<ForumWafRecoveryResult>? _inFlight;
  DateTime? _lastAttempt;
  Future<ForumWafRecoveryResult> Function(ForumWafRecoveryRequest)? _launcher;

  /// Attaches the platform-specific challenge launcher.
  void attach(
    Future<ForumWafRecoveryResult> Function(ForumWafRecoveryRequest) launcher,
  ) => _launcher = launcher;
  @override
  Future<ForumWafRecoveryResult> recover(ForumWafRecoveryRequest request) {
    final running = _inFlight;
    if (running != null) return running;
    final launcher = _launcher;
    if (launcher == null) {
      return Future.value(ForumWafRecoveryResult.unavailable);
    }
    if (_lastAttempt != null && _now().difference(_lastAttempt!) < cooldown) {
      return Future.value(ForumWafRecoveryResult.coolingDown);
    }
    late final Future<ForumWafRecoveryResult> result;
    result = Future(() => launcher(request))
        .then((value) {
          if (value == ForumWafRecoveryResult.verified ||
              value == ForumWafRecoveryResult.cancelled) {
            _lastAttempt = _now();
          }
          return value;
        })
        .catchError((_) => ForumWafRecoveryResult.failed)
        .whenComplete(() {
          if (identical(_inFlight, result)) _inFlight = null;
        });
    _inFlight = result;
    return result;
  }
}
