import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_auth_cookie.dart';

void main() {
  group('YamiboAuthCookie.isLoggedIn', () {
    test('returns true when a valid *_auth cookie is present', () {
      expect(
        YamiboAuthCookie.isLoggedIn(const <String, String>{
          'EeqY_2132_saltkey': 'abc',
          'EeqY_2132_auth': 'sometoken',
        }),
        isTrue,
      );
    });

    test('returns false when the auth cookie is missing', () {
      expect(
        YamiboAuthCookie.isLoggedIn(const <String, String>{
          'EeqY_2132_saltkey': 'abc',
          'acw_sc__v2': 'wafpass',
        }),
        isFalse,
      );
    });

    test('returns false when the auth cookie carries a delete placeholder', () {
      expect(
        YamiboAuthCookie.isLoggedIn(const <String, String>{
          'EeqY_2132_auth': 'deleted',
        }),
        isFalse,
      );
    });

    test('returns false when the auth cookie value is empty', () {
      expect(
        YamiboAuthCookie.isLoggedIn(const <String, String>{
          'EeqY_2132_auth': '   ',
        }),
        isFalse,
      );
    });

    test('is agnostic to the site-specific cookie prefix', () {
      expect(
        YamiboAuthCookie.isLoggedIn(const <String, String>{
          'OtherPrefix_9999_auth': 'token',
        }),
        isTrue,
      );
    });
  });
}
