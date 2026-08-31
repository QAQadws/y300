import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/network/waf/waf.dart';

/// Runs the same ordinary WebView challenge used by the original foreground
/// flow, while its host keeps the platform view behind the application.
class WafChallengeBackgroundWebView extends ConsumerStatefulWidget {
  const WafChallengeBackgroundWebView({
    super.key,
    required this.initialUri,
    required this.onCompleted,
    this.userAgent = BrowserUserAgents.mobile,
    this.timeout = const Duration(seconds: 20),
    this.settleDelay = const Duration(milliseconds: 450),
  });

  final Uri initialUri;
  final String userAgent;
  final ValueChanged<WafChallengeRecoveryResult> onCompleted;
  final Duration timeout;
  final Duration settleDelay;

  @override
  ConsumerState<WafChallengeBackgroundWebView> createState() =>
      _WafChallengeBackgroundWebViewState();
}

class _WafChallengeBackgroundWebViewState
    extends ConsumerState<WafChallengeBackgroundWebView> {
  final Stopwatch _stopwatch = Stopwatch();

  Timer? _evaluationTimer;
  Timer? _timeoutTimer;
  bool _isPrepared = false;
  bool _didComplete = false;
  bool _verificationInFlight = false;
  bool _verificationRequested = false;
  int _navigationGeneration = 0;
  int _probeAttempt = 0;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _timeoutTimer = Timer(
      widget.timeout,
      () => _complete(WafChallengeRecoveryResult.failed),
    );
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _didComplete = true;
    _evaluationTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPrepared) {
      return const SizedBox.expand();
    }
    return inapp.InAppWebView(
      key: const Key('waf-challenge-background-webview'),
      initialUrlRequest: inapp.URLRequest(
        url: inapp.WebUri(widget.initialUri.toString()),
      ),
      initialSettings: buildWafChallengeBackgroundWebViewSettings(
        userAgent: _effectiveUserAgent,
      ),
      onWebViewCreated: (_) {
        _debugEvent('browser_created');
        _scheduleEvaluation(delay: const Duration(milliseconds: 750));
      },
      onLoadStart: (_, _) {
        _navigationGeneration += 1;
        _probeAttempt = 0;
        _scheduleEvaluation(delay: const Duration(milliseconds: 750));
      },
      onPageCommitVisible: (_, _) => _scheduleEvaluation(),
      onUpdateVisitedHistory: (_, _, _) => _scheduleEvaluation(),
      onLoadStop: (_, _) => _scheduleEvaluation(),
      onProgressChanged: (_, progress) {
        if (progress >= 100) {
          _scheduleEvaluation();
        }
      },
      onReceivedError: (_, request, _) {
        if (request.isForMainFrame != false) {
          _scheduleEvaluation();
        }
      },
      onWebContentProcessDidTerminate: (_) {
        _complete(WafChallengeRecoveryResult.failed);
      },
    );
  }

  Future<void> _prepare() async {
    try {
      await ref
          .read(webViewCookieSyncServiceProvider)
          .seedFromStore(widget.initialUri);
    } catch (_) {
      // Match the proven foreground flow: cookie seeding is best-effort and
      // the site's own JavaScript may still establish a fresh clearance.
    }
    if (!mounted || _didComplete) {
      return;
    }
    setState(() => _isPrepared = true);
  }

  void _scheduleEvaluation({Duration? delay}) {
    if (!mounted || _didComplete || !_isPrepared) {
      return;
    }
    if (_verificationInFlight) {
      _verificationRequested = true;
      return;
    }
    _evaluationTimer?.cancel();
    _evaluationTimer = Timer(
      delay ?? widget.settleDelay,
      () => unawaited(_evaluate(_navigationGeneration)),
    );
  }

  Future<void> _evaluate(int navigationGeneration) async {
    if (!mounted || _didComplete || _verificationInFlight) {
      return;
    }
    _verificationInFlight = true;
    _verificationRequested = false;
    WafChallengeClearance clearance = WafChallengeClearance.inconclusive;
    try {
      clearance = await ref
          .read(wafChallengeVerificationServiceProvider)
          .verify(uri: widget.initialUri, userAgent: _effectiveUserAgent);
    } catch (_) {
      // Cookie and transport races are retried while the same WebView stays
      // mounted. The independent deadline always completes the host future.
    } finally {
      _verificationInFlight = false;
    }
    if (!mounted || _didComplete) {
      return;
    }
    _debugEvent('probe_completed', result: clearance.name);
    if (clearance == WafChallengeClearance.cleared) {
      _complete(WafChallengeRecoveryResult.verified);
      return;
    }
    if (navigationGeneration != _navigationGeneration ||
        _verificationRequested) {
      _scheduleEvaluation();
      return;
    }
    _scheduleEvaluation(delay: _nextRetryDelay());
  }

  Duration _nextRetryDelay() {
    return switch (_probeAttempt++) {
      0 => const Duration(milliseconds: 500),
      1 => const Duration(seconds: 1),
      _ => const Duration(seconds: 2),
    };
  }

  void _complete(WafChallengeRecoveryResult result) {
    if (_didComplete || !mounted) {
      return;
    }
    _didComplete = true;
    _evaluationTimer?.cancel();
    _timeoutTimer?.cancel();
    _debugEvent('completed', result: result.name);
    widget.onCompleted(result);
  }

  String get _effectiveUserAgent {
    final value = widget.userAgent.trim();
    return value.isEmpty ? BrowserUserAgents.mobile : value;
  }

  void _debugEvent(String event, {String? result}) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[WAF][background] event=$event'
      '${result == null ? '' : ' result=$result'} '
      'elapsedMs=${_stopwatch.elapsedMilliseconds}',
    );
  }
}

@visibleForTesting
inapp.InAppWebViewSettings buildWafChallengeBackgroundWebViewSettings({
  required String userAgent,
}) {
  return inapp.InAppWebViewSettings(
    javaScriptEnabled: true,
    userAgent: userAgent,
    thirdPartyCookiesEnabled: true,
    clearCache: false,
    transparentBackground: false,
    // This browser never accepts input. Texture-layer composition keeps its
    // lifecycle inside Flutter's compositor instead of switching the whole
    // application surface when the Android platform view is attached.
    useHybridComposition: false,
    needInitialFocus: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableVerticalScroll: true,
    disableHorizontalScroll: true,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
  );
}
