import 'dart:async';

import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/waf/waf_challenge_detector.dart';

/// Result of a foreground WAF recovery attempt.
///
/// [verified] is the only result that permits the transport layer to replay a
/// request. The other values are intentionally explicit so that an
/// unavailable host is not treated like a user cancellation or a successful
/// verification when applying the loop-prevention cooldown.
enum WafChallengeRecoveryResult {
  verified,
  cancelled,
  unavailable,
  coolingDown,
  failed,
}

typedef WafChallengeRecoveryLauncher =
    Future<WafChallengeRecoveryResult> Function(
      WafChallengeRecoveryRequest request,
    );
typedef WafChallengeRecoveryDetach = void Function();

final class WafChallengeRecoveryRequest {
  const WafChallengeRecoveryRequest({
    required this.triggeringUri,
    required this.method,
    required this.evidence,
    this.userAgent = BrowserUserAgents.mobile,
  });

  final Uri triggeringUri;
  final String method;
  final WafChallengeEvidence evidence;
  final String userAgent;
}

/// Bridges transport-level challenge detection to one foreground UI flow.
///
/// The coordinator deliberately knows nothing about Flutter navigation or a
/// WebView. The root presentation host attaches a launcher while mounted. All
/// concurrent challenged requests share one future, and a short cooldown
/// prevents a verified or explicitly cancelled attempt from creating a route
/// loop. An unavailable host never consumes that cooldown.
final class WafChallengeRecoveryCoordinator {
  WafChallengeRecoveryCoordinator({
    Duration retryCooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _retryCooldown = retryCooldown,
       _now = now ?? DateTime.now;

  final Duration _retryCooldown;
  final DateTime Function() _now;

  WafChallengeRecoveryLauncher? _launcher;
  Future<WafChallengeRecoveryResult>? _inFlight;
  DateTime? _lastSuppressedAt;

  WafChallengeRecoveryDetach attachLauncher(
    WafChallengeRecoveryLauncher launcher,
  ) {
    _launcher = launcher;
    return () {
      if (identical(_launcher, launcher)) {
        _launcher = null;
      }
    };
  }

  Future<WafChallengeRecoveryResult> recover(
    WafChallengeRecoveryRequest request,
  ) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final launcher = _launcher;
    if (launcher == null || _isCoolingDown()) {
      return Future<WafChallengeRecoveryResult>.value(
        launcher == null
            ? WafChallengeRecoveryResult.unavailable
            : WafChallengeRecoveryResult.coolingDown,
      );
    }

    late final Future<WafChallengeRecoveryResult> future;
    future = _launchSafely(launcher, request)
        .then((result) {
          if (result == WafChallengeRecoveryResult.verified ||
              result == WafChallengeRecoveryResult.cancelled) {
            _lastSuppressedAt = _now();
          }
          return result;
        })
        .whenComplete(() {
          if (identical(_inFlight, future)) {
            _inFlight = null;
          }
        });
    _inFlight = future;
    return future;
  }

  bool _isCoolingDown() {
    final lastSuppressedAt = _lastSuppressedAt;
    return lastSuppressedAt != null &&
        _now().difference(lastSuppressedAt) < _retryCooldown;
  }

  Future<WafChallengeRecoveryResult> _launchSafely(
    WafChallengeRecoveryLauncher launcher,
    WafChallengeRecoveryRequest request,
  ) async {
    try {
      return await launcher(request);
    } catch (_) {
      return WafChallengeRecoveryResult.failed;
    }
  }
}
