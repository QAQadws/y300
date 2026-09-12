import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';

/// 记录调用的假 cookie jar，避免依赖 flutter_inappwebview 平台通道。
class _FakeWebViewCookieJar implements WebViewCookieJar {
  _FakeWebViewCookieJar(this._cookiesByHost);

  final Map<String, Map<String, String>> _cookiesByHost;
  int clearCount = 0;
  Completer<Map<String, String>>? pendingRead;
  Completer<void>? pendingClear;
  int readCount = 0;

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
    readCount++;
    if (pendingRead != null) return pendingRead!.future;
    return Map<String, String>.from(_cookiesByHost[uri.host] ?? const {});
  }

  @override
  Future<void> writeCookies(Uri uri, Map<String, String> cookies) async {
    _cookiesByHost
        .putIfAbsent(uri.host, () => <String, String>{})
        .addAll(cookies);
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    await pendingClear?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final invalidation in [
    'page',
    'nativeWrite',
    'clearStore',
    'clearBrowser',
  ]) {
    test('pending browser cookies are discarded after $invalidation', () async {
      final uri = Uri.parse('https://bbs.yamibo.com/');
      final store = CookieStore();
      await store.saveCookies(uri, {'auth': 'current'});
      final pending = Completer<Map<String, String>>();
      final jar = _FakeWebViewCookieJar({})..pendingRead = pending;
      final service = WebViewCookieSyncService(
        cookieJar: jar,
        cookieStore: store,
      );
      var active = true;
      final sync = service.syncToStore(uri, isCurrent: () => active);
      switch (invalidation) {
        case 'page':
          active = false;
        case 'nativeWrite':
          await store.saveFromSetCookie(uri, ['auth=new; Path=/']);
        case 'clearStore':
          await store.clear();
        case 'clearBrowser':
          await service.clearWebViewCookies();
      }
      pending.complete({'auth': 'stale'});
      expect(await sync, isEmpty);
      expect(await store.readCookieMap(uri), switch (invalidation) {
        'clearStore' => <String, String>{},
        'nativeWrite' => {'auth': 'new'},
        _ => {'auth': 'current'},
      });
    });
  }

  test(
    'pending and failed browser clears cannot leak an old snapshot',
    () async {
      final uri = Uri.parse('https://bbs.yamibo.com/');
      final jar = _FakeWebViewCookieJar({
        uri.host: {'auth': 'current'},
      })..pendingClear = Completer<void>();
      final store = CookieStore();
      final service = WebViewCookieSyncService(
        cookieJar: jar,
        cookieStore: store,
      );
      final clearing = service.clearWebViewCookies();
      final failed = expectLater(clearing, throwsStateError);
      expect(await service.syncToStore(uri), isEmpty);
      expect(jar.readCount, 0);
      expect(await store.readCookieMap(uri), isEmpty);
      jar.pendingClear!.completeError(StateError('platform unavailable'));
      await failed;
      // A later browser operation may retry after the failed clear, using a new
      // snapshot; work started before or during the clear cannot be replayed.
      expect(await service.syncToStore(uri), {'auth': 'current'});
      expect(jar.readCount, 1);
    },
  );

  test('an expired page does not start a browser read', () async {
    final jar = _FakeWebViewCookieJar({});
    final service = WebViewCookieSyncService(
      cookieJar: jar,
      cookieStore: CookieStore(),
    );
    expect(
      await service.syncToStore(
        Uri.parse('https://bbs.yamibo.com/'),
        isCurrent: () => false,
      ),
      isEmpty,
    );
    expect(jar.readCount, 0);
  });

  test(
    'syncToStore writes WebView cookies into the dio cookie store',
    () async {
      final uri = Uri.parse('https://bbs.yamibo.com/member.php');
      final jar = _FakeWebViewCookieJar(<String, Map<String, String>>{
        'bbs.yamibo.com': <String, String>{
          'acw_sc__v2': 'wafpass',
          'EeqY_2132_auth': 'authtoken',
        },
      });
      final cookieStore = CookieStore();
      final service = WebViewCookieSyncService(
        cookieJar: jar,
        cookieStore: cookieStore,
      );

      final synced = await service.syncToStore(uri);

      expect(synced, <String, String>{
        'acw_sc__v2': 'wafpass',
        'EeqY_2132_auth': 'authtoken',
      });
      expect(await cookieStore.readCookieMap(uri), <String, String>{
        'acw_sc__v2': 'wafpass',
        'EeqY_2132_auth': 'authtoken',
      });
    },
  );

  test('syncToStore preserves existing dio cookies while merging', () async {
    final uri = Uri.parse('https://bbs.yamibo.com/member.php');
    final cookieStore = CookieStore();
    await cookieStore.saveFromSetCookie(uri, const <String>[
      'EeqY_2132_saltkey=salt; Path=/',
    ]);
    final jar = _FakeWebViewCookieJar(<String, Map<String, String>>{
      'bbs.yamibo.com': <String, String>{'acw_sc__v2': 'wafpass'},
    });
    final service = WebViewCookieSyncService(
      cookieJar: jar,
      cookieStore: cookieStore,
    );

    await service.syncToStore(uri);

    expect(await cookieStore.readCookieMap(uri), <String, String>{
      'EeqY_2132_saltkey': 'salt',
      'acw_sc__v2': 'wafpass',
    });
  });

  test(
    'syncToStore returns an empty snapshot without touching the store when WebView has no cookies',
    () async {
      final uri = Uri.parse('https://bbs.yamibo.com/member.php');
      final cookieStore = CookieStore();
      await cookieStore.saveFromSetCookie(uri, const <String>[
        'keep=1; Path=/',
      ]);
      final jar = _FakeWebViewCookieJar(const <String, Map<String, String>>{});
      final service = WebViewCookieSyncService(
        cookieJar: jar,
        cookieStore: cookieStore,
      );

      final synced = await service.syncToStore(uri);

      expect(synced, isEmpty);
      expect(await cookieStore.readCookieMap(uri), <String, String>{
        'keep': '1',
      });
    },
  );

  test('clearWebViewCookies delegates to the cookie jar', () async {
    final jar = _FakeWebViewCookieJar(const <String, Map<String, String>>{});
    final service = WebViewCookieSyncService(
      cookieJar: jar,
      cookieStore: CookieStore(),
    );

    await service.clearWebViewCookies();

    expect(jar.clearCount, 1);
  });

  test('seedFromStore merges native cookies into the WebView jar', () async {
    final uri = Uri.parse('https://bbs.yamibo.com/index.php?mobile=2');
    final cookieStore = CookieStore();
    await cookieStore.saveCookies(uri, const <String, String>{
      'acw_sc__v2': 'native-pass',
      'EeqY_2132_auth': 'auth-token',
    });
    final jar = _FakeWebViewCookieJar(<String, Map<String, String>>{
      'bbs.yamibo.com': <String, String>{'keep': 'webview'},
    });
    final service = WebViewCookieSyncService(
      cookieJar: jar,
      cookieStore: cookieStore,
    );

    final seeded = await service.seedFromStore(uri);

    expect(seeded['acw_sc__v2'], 'native-pass');
    expect(await jar.readCookies(uri), <String, String>{
      'keep': 'webview',
      'acw_sc__v2': 'native-pass',
      'EeqY_2132_auth': 'auth-token',
    });
  });
}
