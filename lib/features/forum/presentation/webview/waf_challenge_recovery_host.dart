import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
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
  static const Duration _surfaceRetirementDeadline = Duration(milliseconds: 80);

  WafChallengeRecoveryDetach? _detachLauncher;
  late final ValueNotifier<_BackgroundRecoveryRun?> _runNotifier;
  _BackgroundRecoveryRun? _activeRun;
  _BackgroundRecoveryRun? _retiringRun;
  bool _isForeground = true;
  int _nextGeneration = 0;
  int _retirementGeneration = 0;
  Timer? _surfaceRetirementTimer;
  Completer<void>? _surfaceRetirementCompleter;

  @override
  void initState() {
    super.initState();
    _runNotifier = ValueNotifier<_BackgroundRecoveryRun?>(null);
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
      _abortRecovery(WafChallengeRecoveryResult.unavailable);
    }
  }

  @override
  void dispose() {
    _detachLauncher?.call();
    _detachLauncher = null;
    WidgetsBinding.instance.removeObserver(this);
    _abortRecovery(
      WafChallengeRecoveryResult.unavailable,
      notifyBackground: false,
    );
    _runNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundBuilder = ref.watch(wafChallengeBackgroundBuilderProvider);
    return Stack(
      key: const Key('waf-challenge-recovery-host'),
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: ValueListenableBuilder<_BackgroundRecoveryRun?>(
            valueListenable: _runNotifier,
            builder: (context, run, _) => _WafChallengeBackgroundSlot(
              run: run,
              backgroundBuilder: backgroundBuilder,
              onCompleted: _finish,
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            key: const Key('waf-challenge-foreground-content'),
            child: widget.child,
          ),
        ),
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
    final existingRun = _activeRun ?? _retiringRun;
    if (existingRun != null) {
      return existingRun.completion.future;
    }
    final run = _BackgroundRecoveryRun(
      generation: ++_nextGeneration,
      request: request,
    );
    _activeRun = run;
    _runNotifier.value = run;
    return run.completion.future;
  }

  void _finish(_BackgroundRecoveryRun run, WafChallengeRecoveryResult result) {
    if (!identical(_activeRun, run)) {
      return;
    }
    _activeRun = null;
    _retiringRun = run;
    _runNotifier.value = null;
    final retirementGeneration = ++_retirementGeneration;
    unawaited(
      _completeAfterSurfaceRetirement(run, result, retirementGeneration),
    );
  }

  Future<void> _completeAfterSurfaceRetirement(
    _BackgroundRecoveryRun run,
    WafChallengeRecoveryResult result,
    int retirementGeneration,
  ) async {
    await _waitForSurfaceRetirement();
    if (!mounted ||
        retirementGeneration != _retirementGeneration ||
        !identical(_retiringRun, run)) {
      return;
    }
    _retiringRun = null;
    if (!run.completion.isCompleted) {
      run.completion.complete(result);
    }
  }

  void _abortRecovery(
    WafChallengeRecoveryResult result, {
    bool notifyBackground = true,
  }) {
    final activeRun = _activeRun;
    final retiringRun = _retiringRun;
    _activeRun = null;
    _retiringRun = null;
    _retirementGeneration += 1;
    _completeSurfaceRetirementWait();
    if (notifyBackground) {
      _runNotifier.value = null;
    }
    _completeRun(activeRun, result);
    if (!identical(retiringRun, activeRun)) {
      _completeRun(retiringRun, result);
    }
  }

  void _completeRun(
    _BackgroundRecoveryRun? run,
    WafChallengeRecoveryResult result,
  ) {
    if (run == null || run.completion.isCompleted) {
      return;
    }
    run.completion.complete(result);
  }

  Future<void> _waitForSurfaceRetirement() {
    _completeSurfaceRetirementWait();
    final completer = Completer<void>();
    _surfaceRetirementCompleter = completer;
    _surfaceRetirementTimer = Timer(
      _surfaceRetirementDeadline,
      _completeSurfaceRetirementWait,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (identical(_surfaceRetirementCompleter, completer)) {
        _completeSurfaceRetirementWait();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    return completer.future;
  }

  void _completeSurfaceRetirementWait() {
    _surfaceRetirementTimer?.cancel();
    _surfaceRetirementTimer = null;
    final completer = _surfaceRetirementCompleter;
    _surfaceRetirementCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _WafChallengeBackgroundSlot extends StatelessWidget {
  const _WafChallengeBackgroundSlot({
    required this.run,
    required this.backgroundBuilder,
    required this.onCompleted,
  });

  final _BackgroundRecoveryRun? run;
  final WafChallengeBackgroundBuilder backgroundBuilder;
  final void Function(
    _BackgroundRecoveryRun run,
    WafChallengeRecoveryResult result,
  )
  onCompleted;

  @override
  Widget build(BuildContext context) {
    final currentRun = run;
    if (currentRun == null) {
      return const SizedBox.expand(key: Key('waf-challenge-background-idle'));
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ExcludeSemantics(
          child: IgnorePointer(
            child: KeyedSubtree(
              key: ValueKey<int>(currentRun.generation),
              child: backgroundBuilder(
                request: currentRun.request,
                onCompleted: (result) => onCompleted(currentRun, result),
              ),
            ),
          ),
        ),
        ColoredBox(
          key: const Key('waf-challenge-background-cover'),
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
      ],
    );
  }
}

final class _BackgroundRecoveryRun {
  _BackgroundRecoveryRun({required this.generation, required this.request});

  final int generation;
  final WafChallengeRecoveryRequest request;
  final Completer<WafChallengeRecoveryResult> completion =
      Completer<WafChallengeRecoveryResult>();
}
