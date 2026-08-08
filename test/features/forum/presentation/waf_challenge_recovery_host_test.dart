import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/waf/waf.dart';
import 'package:y300/features/forum/presentation/webview/waf_challenge_recovery_host.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
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
          evidence: WafChallengeEvidence.scriptBody,
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

      completeRecovery!(WafChallengeRecoveryResult.verified);
      await tester.pump();
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
        evidence: WafChallengeEvidence.httpMethodNotAllowed,
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
}

final class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount += 1;
    super.didPush(route, previousRoute);
  }
}
