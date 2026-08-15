import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/forum/data/services/forum_home_request_profile_resolver.dart';

void main() {
  test(
    'uses persisted auth cookie for logged-in startup cache profile',
    () async {
      final resolver = CookieForumHomeRequestProfileResolver(
        cookieStore: _FakeCookieStore(const <String, String>{
          'EeqY_2132_auth': 'token',
        }),
      );

      expect(await resolver.resolve(), DocumentRequestProfile.loggedIn);
    },
  );

  test('uses anonymous startup cache profile without auth cookie', () async {
    final resolver = CookieForumHomeRequestProfileResolver(
      cookieStore: _FakeCookieStore(const <String, String>{'sid': 'value'}),
    );

    expect(await resolver.resolve(), DocumentRequestProfile.anonymous);
  });
}

class _FakeCookieStore extends CookieStore {
  _FakeCookieStore(this.cookies);

  final Map<String, String> cookies;

  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async => cookies;
}
