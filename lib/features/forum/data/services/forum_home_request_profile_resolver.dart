import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_auth_cookie.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';

abstract interface class ForumHomeRequestProfileResolver {
  Future<DocumentRequestProfile> resolve();
}

class CookieForumHomeRequestProfileResolver
    implements ForumHomeRequestProfileResolver {
  CookieForumHomeRequestProfileResolver({
    required CookieStore cookieStore,
    Uri? siteUri,
  }) : _cookieStore = cookieStore,
       _siteUri = siteUri ?? Uri.parse(AppConfig.siteBaseUrl);

  final CookieStore _cookieStore;
  final Uri _siteUri;

  @override
  Future<DocumentRequestProfile> resolve() async {
    try {
      final cookies = await _cookieStore.readCookieMap(_siteUri);
      return YamiboAuthCookie.isLoggedIn(cookies)
          ? DocumentRequestProfile.loggedIn
          : DocumentRequestProfile.anonymous;
    } catch (_) {
      // A damaged/unavailable cookie snapshot must not turn startup into
      // another blocking dependency. The verified auth state can reconcile
      // the profile afterwards.
      return DocumentRequestProfile.anonymous;
    }
  }
}

final forumHomeRequestProfileResolverProvider =
    Provider<ForumHomeRequestProfileResolver>((ref) {
      return CookieForumHomeRequestProfileResolver(
        cookieStore: ref.watch(cookieStoreProvider),
      );
    });
