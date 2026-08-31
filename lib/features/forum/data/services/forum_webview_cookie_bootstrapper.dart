import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';

final forumWebViewCookieBootstrapperProvider =
    Provider<ForumWebViewCookieBootstrapper>((ref) {
      return DefaultForumWebViewCookieBootstrapper(
        cookieStore: ref.watch(cookieStoreProvider),
      );
    });

abstract interface class ForumWebViewCookieBootstrapper {
  Future<Map<String, String>> buildSeedCookies({required Uri uri});
}

final class DefaultForumWebViewCookieBootstrapper
    implements ForumWebViewCookieBootstrapper {
  const DefaultForumWebViewCookieBootstrapper({
    required CookieStore cookieStore,
  }) : _cookieStore = cookieStore;

  final CookieStore _cookieStore;

  @override
  Future<Map<String, String>> buildSeedCookies({required Uri uri}) async {
    final rawCookies = await _cookieStore.readCookieMap(uri);
    final seedCookies = <String, String>{};
    for (final entry in rawCookies.entries) {
      final name = entry.key.trim();
      final value = entry.value.trim();
      if (name.isEmpty || value.isEmpty || value.toLowerCase() == 'deleted') {
        continue;
      }
      seedCookies[name] = value;
    }
    return seedCookies;
  }
}
