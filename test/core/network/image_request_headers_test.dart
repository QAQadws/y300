import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('buildHeaders adds referer user agent and same-host cookie', () async {
    final cookieStore = CookieStore();
    await cookieStore.saveFromSetCookie(
      Uri.parse('https://bbs.yamibo.com/forum.php'),
      const <String>['auth=token123; Path=/; HttpOnly'],
    );
    final builder = DiscuzImageRequestHeaderBuilder(cookieStore: cookieStore);

    final headers = await builder.buildHeaders(
      'https://bbs.yamibo.com/data/attachment/test.jpg',
    );

    expect(headers['Referer'], 'https://bbs.yamibo.com/');
    expect(headers['User-Agent'], contains('Mozilla/5.0'));
    expect(headers['Accept'], contains('image/'));
    expect(headers['Accept-Language'], contains('zh-CN'));
    expect(headers['Cookie'], 'auth=token123');
  });

  test(
    'buildHeaders does not leak bbs cookie to third-party image host',
    () async {
      final cookieStore = CookieStore();
      await cookieStore.saveFromSetCookie(
        Uri.parse('https://bbs.yamibo.com/forum.php'),
        const <String>['auth=token123; Path=/; HttpOnly'],
      );
      final builder = DiscuzImageRequestHeaderBuilder(cookieStore: cookieStore);

      final headers = await builder.buildHeaders(
        'https://img.example.test/image.jpg',
      );

      expect(headers['Referer'], 'https://bbs.yamibo.com/');
      expect(headers.containsKey('Cookie'), isFalse);
    },
  );
}
