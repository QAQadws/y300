import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/l10n/app_localizations.dart';

/// A visible browser boundary that lets the site's own JavaScript issue the
/// `acw_sc__v2` cookie. It never computes or fabricates the pass in Dart.
class WafChallengeWebViewPage extends ConsumerStatefulWidget {
  const WafChallengeWebViewPage({
    super.key,
    required this.initialUri,
    this.userAgent = BrowserUserAgents.mobile,
    this.timeout = const Duration(seconds: 20),
    this.settleDelay = const Duration(milliseconds: 450),
  });

  static const String routeName = 'waf-security-verification';

  final Uri initialUri;
  final String userAgent;
  final Duration timeout;
  final Duration settleDelay;

  @override
  ConsumerState<WafChallengeWebViewPage> createState() =>
      _WafChallengeWebViewPageState();
}

class _WafChallengeWebViewPageState
    extends ConsumerState<WafChallengeWebViewPage> {
  inapp.InAppWebViewController? _controller;
  Timer? _settleTimer;
  Timer? _timeoutTimer;
  bool _isPrepared = false;
  bool _didComplete = false;
  String? _failureMessage;
  int _progress = 0;
  int _generation = 0;
  int _evaluationGeneration = 0;
  int _probeAttempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('waf-challenge-webview-page'),
      appBar: AppBar(
        title: Text(l10n.networkSecurityVerificationTitle),
        bottom: _isPrepared && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: !_isPrepared
          ? _failureMessage == null
                ? _PreparingView(
                    message: l10n.networkSecurityVerificationPreparing,
                  )
                : _FailureView(
                    message: _failureMessage!,
                    retryLabel: l10n.commonRetry,
                    onRetry: _retry,
                  )
          : Stack(
              fit: StackFit.expand,
              children: [
                inapp.InAppWebView(
                  key: const Key('waf-challenge-webview'),
                  initialUrlRequest: inapp.URLRequest(
                    url: inapp.WebUri(widget.initialUri.toString()),
                  ),
                  initialSettings: inapp.InAppWebViewSettings(
                    javaScriptEnabled: true,
                    userAgent: _effectiveUserAgent,
                    thirdPartyCookiesEnabled: true,
                    clearCache: false,
                    transparentBackground: false,
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    _armTimeout(_generation);
                  },
                  onLoadStart: (_, _) {
                    _settleTimer?.cancel();
                    _evaluationGeneration += 1;
                    _probeAttempt = 0;
                  },
                  onProgressChanged: (_, progress) {
                    if (mounted) {
                      setState(() => _progress = progress);
                    }
                  },
                  onLoadStop: (controller, _) {
                    if (_failureMessage != null || _didComplete) {
                      return;
                    }
                    _scheduleEvaluation(controller, _generation);
                  },
                ),
                if (_failureMessage != null)
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: _FailureView(
                      message: _failureMessage!,
                      retryLabel: l10n.commonRetry,
                      onRetry: _retry,
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _prepare() async {
    final generation = ++_generation;
    try {
      await ref
          .read(webViewCookieSyncServiceProvider)
          .seedFromStore(widget.initialUri);
    } catch (_) {
      // Cookie seeding is best-effort. A clean WebView can still execute the
      // site's challenge and produce a fresh pass for the native client.
    }
    if (!mounted || generation != _generation) {
      return;
    }
    _probeAttempt = 0;
    _evaluationGeneration += 1;
    setState(() {
      _isPrepared = true;
      _failureMessage = null;
    });
  }

  void _scheduleEvaluation(
    inapp.InAppWebViewController controller,
    int generation, {
    Duration? delay,
  }) {
    _settleTimer?.cancel();
    final evaluationGeneration = ++_evaluationGeneration;
    _settleTimer = Timer(delay ?? widget.settleDelay, () {
      unawaited(_evaluate(controller, generation, evaluationGeneration));
    });
  }

  void _scheduleProbeRetry(
    inapp.InAppWebViewController controller,
    int generation,
  ) {
    final delay = switch (_probeAttempt++) {
      0 => const Duration(milliseconds: 500),
      1 => const Duration(seconds: 1),
      _ => const Duration(seconds: 2),
    };
    _scheduleEvaluation(controller, generation, delay: delay);
  }

  Future<void> _evaluate(
    inapp.InAppWebViewController controller,
    int generation,
    int evaluationGeneration,
  ) async {
    if (!mounted ||
        _didComplete ||
        generation != _generation ||
        evaluationGeneration != _evaluationGeneration) {
      return;
    }
    try {
      final clearance = await ref
          .read(wafChallengeVerificationServiceProvider)
          .verify(uri: widget.initialUri, userAgent: _effectiveUserAgent);
      if (!mounted ||
          _didComplete ||
          generation != _generation ||
          evaluationGeneration != _evaluationGeneration) {
        return;
      }
      if (clearance == WafChallengeClearance.cleared) {
        _completeSuccessfully();
      } else {
        _scheduleProbeRetry(controller, generation);
      }
    } catch (_) {
      // Cookie/platform and transient transport races are retried while the
      // same visible WebView remains open. The hard timeout owns the terminal
      // failure state.
      if (mounted &&
          !_didComplete &&
          generation == _generation &&
          evaluationGeneration == _evaluationGeneration) {
        _scheduleProbeRetry(controller, generation);
      }
    }
  }

  void _armTimeout(int generation) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(widget.timeout, () {
      if (!mounted || _didComplete || generation != _generation) {
        return;
      }
      _settleTimer?.cancel();
      _evaluationGeneration += 1;
      setState(() {
        _failureMessage = AppLocalizations.of(
          context,
        ).networkSecurityVerificationFailed;
      });
    });
  }

  Future<void> _retry() async {
    _settleTimer?.cancel();
    _timeoutTimer?.cancel();
    _evaluationGeneration += 1;
    _probeAttempt = 0;
    if (!_isPrepared) {
      setState(() => _failureMessage = null);
      await _prepare();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _failureMessage = null;
      _progress = 0;
    });
    try {
      await ref
          .read(webViewCookieSyncServiceProvider)
          .seedFromStore(widget.initialUri);
    } catch (_) {
      // Keep going with the browser jar as-is; sync after navigation remains
      // the authoritative completion gate.
    }
    if (!mounted || generation != _generation) {
      return;
    }
    _armTimeout(generation);
    try {
      await _controller?.loadUrl(
        urlRequest: inapp.URLRequest(
          url: inapp.WebUri(widget.initialUri.toString()),
        ),
      );
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _failureMessage = AppLocalizations.of(
          context,
        ).networkSecurityVerificationFailed;
      });
    }
  }

  void _completeSuccessfully() {
    if (_didComplete || !mounted) {
      return;
    }
    _didComplete = true;
    _settleTimer?.cancel();
    _timeoutTimer?.cancel();
    _evaluationGeneration += 1;
    Navigator.of(context).pop(WafChallengeRecoveryResult.verified);
  }

  String get _effectiveUserAgent {
    final value = widget.userAgent.trim();
    return value.isEmpty ? BrowserUserAgents.mobile : value;
  }
}

class _PreparingView extends StatelessWidget {
  const _PreparingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
