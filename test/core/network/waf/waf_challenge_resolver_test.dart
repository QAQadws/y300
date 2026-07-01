import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/waf/waf_challenge_passer.dart';
import 'package:y300/core/network/waf/waf_challenge_resolver.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';

/// 受控 passer：记录调用次数，可注入延迟与失败。
class _FakePasser implements WafChallengePasser {
  int calls = 0;
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<void> pass(Uri uri) async {
    calls++;
    if (gate != null) {
      await gate!.future;
    }
    if (failWith != null) {
      throw failWith!;
    }
  }
}

/// 假 cookie jar：resolver 走通后应能读到我们放进去的凭证。
class _FakeWebViewCookieJar implements WebViewCookieJar {
  _FakeWebViewCookieJar(this._byHost);

  final Map<String, Map<String, String>> _byHost;

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
    return Map<String, String>.from(_byHost[uri.host] ?? const {});
  }

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  final siteUri = Uri.parse('https://bbs.yamibo.com');

  ({
    WafChallengeResolver resolver,
    _FakePasser passer,
    CookieStore cookieStore,
    DateTime Function() clockRef,
  }) buildSubject({
    Duration passWindow = const Duration(minutes: 30),
    Map<String, Map<String, String>>? cookiesByHost,
  }) {
    final passer = _FakePasser();
    final cookieStore = CookieStore();
    final syncService = WebViewCookieSyncService(
      cookieJar: _FakeWebViewCookieJar(
        cookiesByHost ??
            <String, Map<String, String>>{
              'bbs.yamibo.com': <String, String>{'acw_sc__v2': 'fresh'},
            },
      ),
      cookieStore: cookieStore,
    );
    var now = DateTime(2026, 7, 1, 12, 0, 0);
    final resolver = WafChallengeResolver(
      challengePasser: passer,
      cookieSyncService: syncService,
      siteUri: siteUri,
      passWindow: passWindow,
      clock: () => now,
    );
    return (
      resolver: resolver,
      passer: passer,
      cookieStore: cookieStore,
      clockRef: () => now,
    );
  }

  test('ensureFreshPass runs passer and syncs cookies into dio store', () async {
    final subject = buildSubject();

    final refreshed =
        await subject.resolver.ensureFreshPass(triggeringUri: siteUri);

    expect(refreshed, isTrue);
    expect(subject.passer.calls, 1);
    expect(
      await subject.cookieStore.readCookieMap(siteUri),
      <String, String>{'acw_sc__v2': 'fresh'},
    );
  });

  test('ensureFreshPass skips within the pass window after a success', () async {
    final subject = buildSubject(passWindow: const Duration(minutes: 30));

    final first =
        await subject.resolver.ensureFreshPass(triggeringUri: siteUri);
    final second =
        await subject.resolver.ensureFreshPass(triggeringUri: siteUri);

    expect(first, isTrue);
    expect(second, isFalse);
    expect(subject.passer.calls, 1,
        reason: 'second attempt inside the pass window must not spawn a new WebView');
  });

  test('ensureFreshPass deduplicates concurrent callers', () async {
    final passer = _FakePasser()..gate = Completer<void>();
    final cookieStore = CookieStore();
    final resolver = WafChallengeResolver(
      challengePasser: passer,
      cookieSyncService: WebViewCookieSyncService(
        cookieJar: _FakeWebViewCookieJar(const <String, Map<String, String>>{}),
        cookieStore: cookieStore,
      ),
      siteUri: siteUri,
    );

    final future1 = resolver.ensureFreshPass(triggeringUri: siteUri);
    final future2 = resolver.ensureFreshPass(triggeringUri: siteUri);
    final future3 = resolver.ensureFreshPass(triggeringUri: siteUri);
    // Release the gate so the single in-flight passer completes.
    passer.gate!.complete();

    final results = await Future.wait([future1, future2, future3]);
    expect(results, everyElement(isTrue));
    expect(passer.calls, 1,
        reason: 'all three concurrent triggers should share one refresh');
  });

  test('ensureFreshPass returns false when passer throws and stays retryable', () async {
    final passer = _FakePasser()..failWith = StateError('platform channel missing');
    final resolver = WafChallengeResolver(
      challengePasser: passer,
      cookieSyncService: WebViewCookieSyncService(
        cookieJar: _FakeWebViewCookieJar(const <String, Map<String, String>>{}),
        cookieStore: CookieStore(),
      ),
      siteUri: siteUri,
    );

    final first = await resolver.ensureFreshPass(triggeringUri: siteUri);
    final second = await resolver.ensureFreshPass(triggeringUri: siteUri);

    expect(first, isFalse);
    expect(second, isFalse);
    expect(passer.calls, 2,
        reason: 'a failed refresh must not populate the pass window; '
            'subsequent attempts must retry');
  });

  test('ensureFreshPass refreshes again after the pass window elapses', () async {
    // Non-constructor test since we need to advance the clock. Build inline.
    final passer = _FakePasser();
    final cookieStore = CookieStore();
    var now = DateTime(2026, 7, 1, 12, 0, 0);
    final resolver = WafChallengeResolver(
      challengePasser: passer,
      cookieSyncService: WebViewCookieSyncService(
        cookieJar: _FakeWebViewCookieJar(<String, Map<String, String>>{
          'bbs.yamibo.com': <String, String>{'acw_sc__v2': 'fresh'},
        }),
        cookieStore: cookieStore,
      ),
      siteUri: siteUri,
      passWindow: const Duration(minutes: 30),
      clock: () => now,
    );

    await resolver.ensureFreshPass(triggeringUri: siteUri);
    // Fast-forward past the pass window.
    now = now.add(const Duration(minutes: 31));
    await resolver.ensureFreshPass(triggeringUri: siteUri);

    expect(passer.calls, 2);
  });
}
