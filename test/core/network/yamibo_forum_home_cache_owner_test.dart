import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo_forum_home_cache_owner.dart';

void main() {
  final site = Uri.parse('https://bbs.example.invalid');
  late CookieStore cookies;
  late Y300ForumHomeCacheOwnerStore owners;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cookies = CookieStore();
    owners = Y300ForumHomeCacheOwnerStore(cookies: cookies, siteUri: site);
  });

  Future<void> remember() async {
    await cookies.saveCookies(site, {'fixture_auth': 'session-42'});
    await owners.remember(accountId: '42', isCurrent: () => true);
  }

  test('cold stores restore only a digest-bound cache owner', () async {
    await remember();
    final cold = Y300ForumHomeCacheOwnerStore(
      cookies: CookieStore(),
      siteUri: site,
    );
    final restored = await cold.restore(isCurrent: () => true);
    expect(restored?.accountId, '42');
    expect(restored?.isCurrent, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(TechnicalStorageKeys.forumHomeCacheOwnerV1),
      isNot(contains('session-42')),
    );
  });

  test(
    'WAF cookie changes retain the binding but expire an in-flight read',
    () async {
      await remember();
      final previous = await owners.restore(isCurrent: () => true);
      await cookies.saveCookies(site, {'waf': 'renewed'});
      expect(previous?.isCurrent, isFalse);
      expect((await owners.restore(isCurrent: () => true))?.accountId, '42');
    },
  );

  test(
    'different credentials and logout cannot restore an earlier owner',
    () async {
      await remember();
      await cookies.saveCookies(site, {'fixture_auth': 'session-43'});
      expect(await owners.restore(isCurrent: () => true), isNull);
      await cookies.clear();
      expect(await owners.restore(isCurrent: () => true), isNull);
    },
  );

  test('expired ownership cannot publish a late persisted binding', () async {
    await cookies.saveCookies(site, {'fixture_auth': 'session-42'});
    final pending = Completer<SharedPreferences>();
    final delayed = Y300ForumHomeCacheOwnerStore(
      cookies: cookies,
      siteUri: site,
      preferencesLoader: () => pending.future,
    );
    var current = true;
    final write = delayed.remember(accountId: '42', isCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete(await SharedPreferences.getInstance());
    await write;
    expect(await owners.restore(isCurrent: () => true), isNull);
  });

  test(
    'pending persistence cannot associate a replacement login cookie',
    () async {
      await cookies.saveCookies(site, {'fixture_auth': 'session-42'});
      final pending = Completer<SharedPreferences>();
      final started = Completer<void>();
      final delayed = Y300ForumHomeCacheOwnerStore(
        cookies: cookies,
        siteUri: site,
        preferencesLoader: () {
          started.complete();
          return pending.future;
        },
      );
      final write = delayed.remember(accountId: '42', isCurrent: () => true);
      await started.future;
      await cookies.saveCookies(site, {'fixture_auth': 'session-43'});
      pending.complete(await SharedPreferences.getInstance());
      await write;
      expect(await owners.restore(isCurrent: () => true), isNull);
    },
  );

  test(
    'corruption, other sites and unverified identities are cache misses',
    () async {
      await remember();
      expect(await owners.restore(isCurrent: () => false), isNull);
      expect(
        await Y300ForumHomeCacheOwnerStore(
          cookies: cookies,
          siteUri: Uri.parse('https://other.example.invalid'),
        ).restore(isCurrent: () => true),
        isNull,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        TechnicalStorageKeys.forumHomeCacheOwnerV1,
        '{',
      );
      await owners.remember(accountId: 'unverified', isCurrent: () => true);
      expect(await owners.restore(isCurrent: () => true), isNull);
    },
  );
}
