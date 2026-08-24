/// Evidence accepted by the package WAF coordinator.
enum ForumWafEvidence { httpStatus405 }

/// Result returned by a Host WAF recovery implementation.
enum ForumWafRecoveryResult {
  verified,
  cancelled,
  unavailable,
  coolingDown,
  failed,
}

/// Native probe outcome after a Host challenge attempt.
enum ForumWafClearance { cleared, challenged, inconclusive }

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
