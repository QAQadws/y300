import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/forum/domain/services/forum_webview_cookie_bootstrapper.dart';

void main() {
  test('buildSeedCookies decodes encoded cookie values exactly once', () async {
    final bootstrapper = DefaultForumWebViewCookieBootstrapper(
      cookieStore: _FakeCookieStore(
        cookies: <String, String>{
          'auth': 'token%2Bvalue',
          'lastcheckfeed': '597454%7C1717530000',
          'lip': '127.0.0.1%2C1717530000',
        },
      ),
    );

    final result = await bootstrapper.buildSeedCookies(
      uri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
    );

    expect(
      result,
      <String, String>{
        'auth': 'token+value',
        'lastcheckfeed': '597454|1717530000',
        'lip': '127.0.0.1,1717530000',
      },
    );
  });

  test('buildSeedCookies skips deleted or empty cookies and falls back on decode failure', () async {
    final bootstrapper = DefaultForumWebViewCookieBootstrapper(
      cookieStore: _FakeCookieStore(
        cookies: <String, String>{
          'auth': 'abc%ZZ',
          'deletedCookie': 'deleted',
          'emptyCookie': '',
        },
      ),
    );

    final result = await bootstrapper.buildSeedCookies(
      uri: Uri.parse('https://bbs.yamibo.com/index.php?mobile=2'),
    );

    expect(
      result,
      <String, String>{'auth': 'abc%ZZ'},
    );
  });
}

class _FakeCookieStore extends CookieStore {
  _FakeCookieStore({required this.cookies});

  final Map<String, String> cookies;

  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async {
    return Map<String, String>.from(cookies);
  }
}
