import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';

/// 记录调用的假 cookie jar，避免依赖 flutter_inappwebview 平台通道。
class _FakeWebViewCookieJar implements WebViewCookieJar {
  _FakeWebViewCookieJar(this._cookiesByHost);

  final Map<String, Map<String, String>> _cookiesByHost;
  int clearCount = 0;

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
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
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
