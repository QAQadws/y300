import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/features/forum/presentation/webview/waf_challenge_background_webview.dart';

typedef WafChallengeBackgroundBuilder =
    Widget Function({
      required WafChallengeRecoveryRequest request,
      required ValueChanged<WafChallengeRecoveryResult> onCompleted,
    });

final wafChallengeBackgroundBuilderProvider =
    Provider<WafChallengeBackgroundBuilder>((ref) {
      return ({required request, required onCompleted}) {
        return WafChallengeBackgroundWebView(
          initialUri: _safeVerificationUri,
          userAgent: request.userAgent,
          onCompleted: onCompleted,
        );
      };
    });

final Uri _safeVerificationUri = Uri.parse(AppConfig.siteBaseUrl).replace(
  path: '/index.php',
  queryParameters: const <String, String>{'mobile': '2'},
  fragment: '',
);

/// Application-root bridge that mounts one ordinary WebView behind the app.
///
/// This keeps the browser lifecycle used by the proven foreground flow while
/// avoiding a route, visible challenge UI, pointer input, or semantics.
class WafChallengeRecoveryHost extends ConsumerStatefulWidget {
  const WafChallengeRecoveryHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WafChallengeRecoveryHost> createState() =>
      _WafChallengeRecoveryHostState();
}

class _WafChallengeRecoveryHostState
    extends ConsumerState<WafChallengeRecoveryHost>
    with WidgetsBindingObserver {
  WafChallengeRecoveryDetach? _detachLauncher;
  _BackgroundRecoveryRun? _activeRun;
  bool _isForeground = true;
  int _nextGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _detachLauncher = ref
        .read(wafChallengeRecoveryCoordinatorProvider)
        .attachLauncher(_launchBackgroundRecovery);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (!_isForeground) {
      _finishActive(WafChallengeRecoveryResult.unavailable);
    }
  }

  @override
  void dispose() {
    _detachLauncher?.call();
    _detachLauncher = null;
    WidgetsBinding.instance.removeObserver(this);
    _finishActive(
      WafChallengeRecoveryResult.unavailable,
      notifyListeners: false,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = _activeRun;
    final backgroundBuilder = ref.watch(wafChallengeBackgroundBuilderProvider);
    return Stack(
      key: const Key('waf-challenge-recovery-host'),
      fit: StackFit.expand,
      children: <Widget>[
        if (run != null)
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: KeyedSubtree(
                  key: ValueKey<int>(run.generation),
                  child: backgroundBuilder(
                    request: run.request,
                    onCompleted: (result) => _finish(run, result),
                  ),
                ),
              ),
            ),
          ),
        if (run != null)
          Positioned.fill(
            key: const Key('waf-challenge-background-cover'),
            child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ),
        widget.child,
      ],
    );
  }

  Future<WafChallengeRecoveryResult> _launchBackgroundRecovery(
    WafChallengeRecoveryRequest request,
  ) {
    if (!mounted || !_isForeground) {
      return Future<WafChallengeRecoveryResult>.value(
        WafChallengeRecoveryResult.unavailable,
      );
    }
    final activeRun = _activeRun;
    if (activeRun != null) {
      return activeRun.completion.future;
    }
    final run = _BackgroundRecoveryRun(
      generation: ++_nextGeneration,
      request: request,
    );
    setState(() => _activeRun = run);
    return run.completion.future;
  }

  void _finish(_BackgroundRecoveryRun run, WafChallengeRecoveryResult result) {
    if (!identical(_activeRun, run)) {
      return;
    }
    _finishActive(result);
  }

  void _finishActive(
    WafChallengeRecoveryResult result, {
    bool notifyListeners = true,
  }) {
    final run = _activeRun;
    if (run == null) {
      return;
    }
    _activeRun = null;
    if (notifyListeners && mounted) {
      setState(() {});
    }
    if (!run.completion.isCompleted) {
      run.completion.complete(result);
    }
  }
}

final class _BackgroundRecoveryRun {
  _BackgroundRecoveryRun({required this.generation, required this.request});

  final int generation;
  final WafChallengeRecoveryRequest request;
  final Completer<WafChallengeRecoveryResult> completion =
      Completer<WafChallengeRecoveryResult>();
}
