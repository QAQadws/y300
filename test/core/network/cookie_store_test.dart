import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/network/cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'saveFromSetCookie removes cookies when set-cookie carries delete semantics',
    () async {
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/api/mobile/index.php');

      await cookieStore.saveFromSetCookie(uri, const <String>[
        'auth=token123; Path=/; HttpOnly',
        'saltkey=alive; Path=/; HttpOnly',
      ]);
      await cookieStore.saveFromSetCookie(uri, const <String>[
        'auth=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/',
        'saltkey=; Max-Age=0; Path=/',
      ]);

      expect(await cookieStore.readCookieMap(uri), isEmpty);
      expect(await cookieStore.readCookieHeader(uri), isNull);
    },
  );

  test(
    'readCookieHeader keeps original encoded cookie values for API requests',
    () async {
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/api/mobile/index.php');

      await cookieStore.saveFromSetCookie(uri, const <String>[
        'auth=abc%2Bdef; Path=/; HttpOnly',
        'lastcheckfeed=597454%7C1717530000; Path=/; HttpOnly',
      ]);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(TechnicalStorageKeys.networkCookiesV1),
        isTrue,
      );

      expect(
        await cookieStore.readCookieHeader(uri),
        'auth=abc%2Bdef; lastcheckfeed=597454%7C1717530000',
      );
    },
  );

  test(
    'readCookieMap returns the stored raw cookie map without decode',
    () async {
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/api/mobile/index.php');

      await cookieStore.saveFromSetCookie(uri, const <String>[
        'auth=abc%2Bdef; Path=/; HttpOnly',
        'lip=127.0.0.1%2C1717530000; Path=/; HttpOnly',
      ]);

      expect(await cookieStore.readCookieMap(uri), <String, String>{
        'auth': 'abc%2Bdef',
        'lip': '127.0.0.1%2C1717530000',
      });
    },
  );

  test(
    'saveCookies merges new cookies while keeping existing host cookies',
    () async {
      final cookieStore = CookieStore();
      final uri = Uri.parse('https://bbs.yamibo.com/member.php');

      await cookieStore.saveFromSetCookie(uri, const <String>[
        'saltkey=alive; Path=/; HttpOnly',
      ]);
      // 模拟 WebView 反向同步：新增 WAF 通行证 + 登录态，同时更新已有 saltkey。
      await cookieStore.saveCookies(uri, const <String, String>{
        'acw_sc__v2': 'wafpass',
        'EeqY_2132_auth': 'authtoken',
        'saltkey': 'refreshed',
      });

      expect(await cookieStore.readCookieMap(uri), <String, String>{
        'saltkey': 'refreshed',
        'acw_sc__v2': 'wafpass',
        'EeqY_2132_auth': 'authtoken',
      });
    },
  );

  test('saveCookies drops entries with empty or deleted values', () async {
    final cookieStore = CookieStore();
    final uri = Uri.parse('https://bbs.yamibo.com/member.php');

    await cookieStore.saveCookies(uri, const <String, String>{
      'keep': 'yes',
      'gone': '',
      'stale': 'deleted',
    });

    expect(await cookieStore.readCookieMap(uri), <String, String>{
      'keep': 'yes',
    });
  });

  test('saveCookies is a no-op for an empty map', () async {
    final cookieStore = CookieStore();
    final uri = Uri.parse('https://bbs.yamibo.com/member.php');

    await cookieStore.saveFromSetCookie(uri, const <String>[
      'auth=token123; Path=/; HttpOnly',
    ]);
    await cookieStore.saveCookies(uri, const <String, String>{});

    expect(await cookieStore.readCookieMap(uri), <String, String>{
      'auth': 'token123',
    });
  });
}
