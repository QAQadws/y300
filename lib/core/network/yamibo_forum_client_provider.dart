import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/browser_user_agents.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo_forum_client_bridges.dart';
import 'package:y300/features/auth/data/providers/auth_formhash_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';

/// Process-wide package facade. During 4-B its adapters still use Y300's
/// existing transport and cache services through explicit bridges.
final yamiboForumClientConfigProvider = Provider<ForumClientConfig>((ref) {
  return ForumClientConfig(
    siteOrigin: Uri.parse(AppConfig.siteBaseUrl),
    apiOrigin: Uri.parse(AppConfig.apiBaseUrl),
    userAgent: BrowserUserAgents.mobile,
    desktopUserAgent: BrowserUserAgents.desktop,
    apiUserAgent: BrowserUserAgents.mobile,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
  );
});

final yamiboForumClientNetworkProvider = Provider<ForumClientNetwork>((ref) {
  return YamiboGatewayForumClientNetwork(
    gateway: ref.watch(yamiboHttpGatewayProvider),
    apiOrigin: Uri.parse(AppConfig.apiBaseUrl),
  );
});

final yamiboForumClientAdapterFactoryProvider =
    Provider<ForumClientAdapterFactory>((ref) {
      return ForumClientAdapterFactory(
        config: ref.watch(yamiboForumClientConfigProvider),
        network: ref.watch(yamiboForumClientNetworkProvider),
        sessionStore: ref.watch(yamiboForumSessionStoreProvider),
        documentStore: ref.watch(yamiboForumDocumentStoreProvider),
        snapshotStore: ref.watch(yamiboForumSnapshotStoreProvider),
      );
    });

final yamiboForumClientProvider = Provider<YamiboForumClient>((ref) {
  final factory = ref.watch(yamiboForumClientAdapterFactoryProvider);
  return YamiboForumClient(
    config: ref.watch(yamiboForumClientConfigProvider),
    network: ref.watch(yamiboForumClientNetworkProvider),
    sourcePlan: ForumClientSourcePlan(
      forumDirectory: factory.createHtmlForumDirectory(),
      forumTagDirectory: factory.createForumTagDirectory(),
      forumDisplay: factory.createHtmlForumDisplay(),
      favoriteForumDirectory: factory.createFavoriteForumDirectory(),
      favoriteThreadDirectory: factory.createFavoriteThreadDirectory(),
      currentUserProfile: factory.createCurrentUserProfile(),
      forumUserProfile: factory.createForumUserProfile(),
      userBlogDirectory: factory.createUserBlogDirectory(),
      userBlogDetail: factory.createUserBlogDetail(),
      forumSearch: factory.createForumSearch(
        ref.watch(yamiboForumFormhashProvider),
      ),
      comicEpisodeCatalog: factory.createApiComicEpisodeCatalog(),
      comicThreadDiscovery: factory.createApiComicThreadDiscovery(),
      threadReplyPage: factory.createApiThreadReplyPage(),
      threadDetail: factory.createHtmlThreadDetail(),
    ),
  );
});

final yamiboForumFormhashProvider = Provider<ForumFormhashProvider>((ref) {
  return Y300ForumFormhashProvider(ref.watch(formhashProvider));
});

final yamiboForumSessionStoreProvider = Provider<ForumSessionStore>((ref) {
  return Y300ForumSessionStore(ref.watch(yamiboSessionStoreProvider));
});

final yamiboForumDocumentStoreProvider = Provider<ForumDocumentStore>((ref) {
  return Y300ForumDocumentStore(ref.watch(documentCacheServiceProvider));
});

final yamiboForumSnapshotStoreProvider = Provider<ForumSnapshotStore>((ref) {
  return Y300ForumSnapshotStore(ref.watch(parsedSnapshotCacheServiceProvider));
});
