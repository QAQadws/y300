enum ForumWafEvidence { scriptBody, methodNotAllowed }

enum ForumWafRecoveryResult {
  verified,
  cancelled,
  unavailable,
  coolingDown,
  failed,
}

enum ForumWafClearance { cleared, challenged, inconclusive }

typedef ForumWafCookieSync = Future<void> Function(Uri uri);
typedef ForumWafClearanceProbe =
    Future<ForumWafClearance> Function({
      required Uri uri,
      required String userAgent,
    });

final class ForumWafVerificationService {
  const ForumWafVerificationService({
    required this._syncCookies,
    required this._probe,
  });

  final ForumWafCookieSync _syncCookies;
  final ForumWafClearanceProbe _probe;

  Future<ForumWafClearance> verify({
    required Uri uri,
    required String userAgent,
  }) async {
    await _syncCookies(uri);
    return _probe(uri: uri, userAgent: userAgent);
  }
}

final class ForumWafRecoveryRequest {
  const ForumWafRecoveryRequest({
    required this.uri,
    required this.method,
    required this.evidence,
    required this.userAgent,
  });
  final Uri uri;
  final String method;
  final ForumWafEvidence evidence;
  final String userAgent;
}

abstract interface class ForumWafRecoveryDelegate {
  Future<ForumWafRecoveryResult> recover(ForumWafRecoveryRequest request);
}

final class ForumWafCoordinator implements ForumWafRecoveryDelegate {
  ForumWafCoordinator({
    this.cooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final Duration cooldown;
  final DateTime Function() _now;
  Future<ForumWafRecoveryResult>? _inFlight;
  DateTime? _lastAttempt;
  Future<ForumWafRecoveryResult> Function(ForumWafRecoveryRequest)? _launcher;
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
