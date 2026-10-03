import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
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

  testWidgets('timed out recovery cannot finish seeding browser cookies', (
    tester,
  ) async {
    final cookieStore = _DelayedReadCookieStore();
    final cookieJar = _RecordingWebViewCookieJar();
    WafChallengeRecoveryResult? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webViewCookieSyncServiceProvider.overrideWithValue(
            WebViewCookieSyncService(
              cookieJar: cookieJar,
              cookieStore: cookieStore,
            ),
          ),
        ],
        child: LocalizedTestApp(
          home: WafChallengeBackgroundWebView(
            initialUri: Uri.parse('https://bbs.yamibo.com/'),
            timeout: const Duration(milliseconds: 20),
            onCompleted: (value) => result = value,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(result, WafChallengeRecoveryResult.failed);
    cookieStore.pendingRead.complete({'auth': 'expired-account'});
    await tester.pump();

    expect(cookieJar.writeCount, 0);
    expect(
      find.byKey(const Key('waf-challenge-background-webview')),
      findsNothing,
    );
  });

  for (final transition in ['accountSwitch', 'logout', 'confirmAnonymous']) {
    testWidgets('WAF bootstrap handles identity transition $transition', (
      tester,
    ) async {
      final cookieStore = _DelayedReadCookieStore();
      final cookieJar = _RecordingWebViewCookieJar();
      final sessionStore = YamiboSessionStore();
      if (transition != 'confirmAnonymous') {
        sessionStore.saveExtracted(_sessionSnapshot(uid: '42'));
      }
      WafChallengeRecoveryResult? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yamiboSessionStoreProvider.overrideWithValue(sessionStore),
            webViewCookieSyncServiceProvider.overrideWithValue(
              WebViewCookieSyncService(
                cookieJar: cookieJar,
                cookieStore: cookieStore,
              ),
            ),
          ],
          child: LocalizedTestApp(
            home: WafChallengeBackgroundWebView(
              initialUri: Uri.parse('https://bbs.yamibo.com/'),
              timeout: const Duration(milliseconds: 20),
              onCompleted: (value) => result = value,
            ),
          ),
        ),
      );
      switch (transition) {
        case 'accountSwitch':
          sessionStore.saveExtracted(_sessionSnapshot(uid: '43'));
        case 'logout':
          sessionStore.clear();
        case 'confirmAnonymous':
          sessionStore.saveExtracted(_sessionSnapshot(uid: ''));
      }

      expect(
        result,
        transition == 'confirmAnonymous'
            ? isNull
            : WafChallengeRecoveryResult.unavailable,
      );
      await tester.pump(const Duration(milliseconds: 20));
      cookieStore.pendingRead.complete({'auth': 'expired-account'});
      await tester.pump();

      expect(cookieJar.writeCount, 0);
      expect(
        result,
        transition == 'confirmAnonymous'
            ? WafChallengeRecoveryResult.failed
            : WafChallengeRecoveryResult.unavailable,
      );
    });
  }

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

final class _DelayedReadCookieStore extends CookieStore {
  final Completer<Map<String, String>> pendingRead =
      Completer<Map<String, String>>();

  @override
  Future<Map<String, String>> readCookieMap(Uri uri) => pendingRead.future;
}

final class _RecordingWebViewCookieJar implements WebViewCookieJar {
  int writeCount = 0;

  @override
  Future<Map<String, String>> readCookies(Uri uri) async => {};

  @override
  Future<void> writeCookies(Uri uri, Map<String, String> cookies) async {
    writeCount++;
  }

  @override
  Future<void> clear() async {}
}

YamiboSessionSnapshot _sessionSnapshot({required String uid}) =>
    YamiboSessionSnapshot(
      isLoggedIn: uid.isNotEmpty,
      uid: uid,
      username: uid.isNotEmpty ? 'reader' : '',
      formhash: 'test-formhash',
      updatedAt: DateTime(2026),
      source: 'test',
    );
