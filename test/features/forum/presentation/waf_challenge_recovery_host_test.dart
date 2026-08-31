import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/features/forum/presentation/webview/waf_challenge_background_webview.dart';
import 'package:y300/features/forum/presentation/webview/waf_challenge_recovery_host.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  test('background browser uses non-interactive texture composition', () {
    final settings = buildWafChallengeBackgroundWebViewSettings(
      userAgent: 'test-agent',
    );

    expect(settings.useHybridComposition, isFalse);
    expect(settings.needInitialFocus, isFalse);
    expect(settings.verticalScrollBarEnabled, isFalse);
    expect(settings.horizontalScrollBarEnabled, isFalse);
    expect(settings.disableVerticalScroll, isTrue);
    expect(settings.disableHorizontalScroll, isTrue);
    expect(settings.supportZoom, isFalse);
    expect(settings.builtInZoomControls, isFalse);
    expect(settings.displayZoomControls, isFalse);
    expect(settings.javaScriptEnabled, isTrue);
    expect(settings.thirdPartyCookiesEnabled, isTrue);
    expect(settings.userAgent, 'test-agent');
  });

  testWidgets(
    'mounts one ordinary browser behind the app without pushing a route',
    (tester) async {
      final coordinator = WafChallengeRecoveryCoordinator(
        retryCooldown: Duration.zero,
      );
      final observer = _CountingNavigatorObserver();
      ValueChanged<WafChallengeRecoveryResult>? completeRecovery;
      WafChallengeRecoveryRequest? browserRequest;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wafChallengeRecoveryCoordinatorProvider.overrideWithValue(
              coordinator,
            ),
            wafChallengeBackgroundBuilderProvider.overrideWithValue(({
              required request,
              required onCompleted,
            }) {
              browserRequest = request;
              completeRecovery = onCompleted;
              return const ColoredBox(
                key: Key('fake-waf-background-webview'),
                color: Colors.red,
              );
            }),
          ],
          child: LocalizedTestApp(
            navigatorObservers: <NavigatorObserver>[observer],
            home: const WafChallengeRecoveryHost(
              child: Scaffold(body: Text('home')),
            ),
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final pushesBeforeRecovery = observer.pushCount;

      final recovery = coordinator.recover(
        WafChallengeRecoveryRequest(
          triggeringUri: Uri.parse('https://bbs.yamibo.com/thread-1-1-1.html'),
          method: 'GET',
          evidence: WafChallengeEvidence.httpStatus405,
          userAgent: 'test-agent',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(browserRequest?.userAgent, 'test-agent');
      expect(
        find.byKey(const Key('fake-waf-background-webview')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('waf-challenge-background-cover')),
        findsOneWidget,
      );
      expect(find.text('home'), findsOneWidget);
      expect(observer.pushCount, pushesBeforeRecovery);

      var recoveryCompleted = false;
      unawaited(recovery.then((_) => recoveryCompleted = true));
      completeRecovery!(WafChallengeRecoveryResult.verified);
      expect(recoveryCompleted, isFalse);
      expect(
        find.byKey(const Key('fake-waf-background-webview')),
        findsOneWidget,
      );

      await tester.pump();
      expect(recoveryCompleted, isTrue);
      expect(await recovery, WafChallengeRecoveryResult.verified);
      expect(
        find.byKey(const Key('fake-waf-background-webview')),
        findsNothing,
      );
    },
  );

  testWidgets('removes the browser and completes when the app pauses', (
    tester,
  ) async {
    final coordinator = WafChallengeRecoveryCoordinator(
      retryCooldown: Duration.zero,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wafChallengeRecoveryCoordinatorProvider.overrideWithValue(
            coordinator,
          ),
          wafChallengeBackgroundBuilderProvider.overrideWithValue(({
            required request,
            required onCompleted,
          }) {
            return const SizedBox(key: Key('fake-waf-background-webview'));
          }),
        ],
        child: const LocalizedTestApp(
          home: WafChallengeRecoveryHost(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final recovery = coordinator.recover(
      WafChallengeRecoveryRequest(
        triggeringUri: Uri.parse('https://bbs.yamibo.com/index.php'),
        method: 'GET',
        evidence: WafChallengeEvidence.httpStatus405,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('fake-waf-background-webview')),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final result = await recovery;
    expect(result, WafChallengeRecoveryResult.unavailable);

    // Flutter suppresses frames while paused. The host has already completed
    // the run; the pending removal is rendered on the next resumed frame.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('fake-waf-background-webview')), findsNothing);
  });

  testWidgets('keeps the foreground subtree mounted during recovery', (
    tester,
  ) async {
    final coordinator = WafChallengeRecoveryCoordinator(
      retryCooldown: Duration.zero,
    );
    ValueChanged<WafChallengeRecoveryResult>? completeRecovery;
    var initCount = 0;
    var buildCount = 0;
    var disposeCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wafChallengeRecoveryCoordinatorProvider.overrideWithValue(
            coordinator,
          ),
          wafChallengeBackgroundBuilderProvider.overrideWithValue(({
            required request,
            required onCompleted,
          }) {
            completeRecovery = onCompleted;
            return const SizedBox(key: Key('fake-waf-background-webview'));
          }),
        ],
        child: LocalizedTestApp(
          home: WafChallengeRecoveryHost(
            child: Scaffold(
              appBar: AppBar(title: const Text('stable app bar')),
              body: _ForegroundLifecycleProbe(
                onInit: () => initCount += 1,
                onBuild: () => buildCount += 1,
                onDispose: () => disposeCount += 1,
              ),
            ),
          ),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final initialBuildCount = buildCount;

    final recovery = coordinator.recover(
      WafChallengeRecoveryRequest(
        triggeringUri: Uri.parse('https://bbs.yamibo.com/index.php'),
        method: 'GET',
        evidence: WafChallengeEvidence.httpStatus405,
      ),
    );
    await tester.pump();

    expect(find.text('stable app bar'), findsOneWidget);
    expect(initCount, 1);
    expect(buildCount, initialBuildCount);
    expect(disposeCount, 0);

    completeRecovery!(WafChallengeRecoveryResult.verified);
    await tester.pump();
    expect(await recovery, WafChallengeRecoveryResult.verified);
    expect(find.text('stable app bar'), findsOneWidget);
    expect(initCount, 1);
    expect(buildCount, initialBuildCount);
    expect(disposeCount, 0);
  });
}

class _ForegroundLifecycleProbe extends StatefulWidget {
  const _ForegroundLifecycleProbe({
    required this.onInit,
    required this.onBuild,
    required this.onDispose,
  });

  final VoidCallback onInit;
  final VoidCallback onBuild;
  final VoidCallback onDispose;

  @override
  State<_ForegroundLifecycleProbe> createState() =>
      _ForegroundLifecycleProbeState();
}

class _ForegroundLifecycleProbeState extends State<_ForegroundLifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const Text('stable foreground');
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

final class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount += 1;
    super.didPush(route, previousRoute);
  }
}
