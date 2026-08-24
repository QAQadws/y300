import '../adapters/forum_client_adapter_factory.dart';
import '../cache/forum_cache.dart';
import '../contracts/forum_resource.dart';
import '../contracts/sticker_catalog.dart';
import '../network/forum_network.dart';
import '../session/forum_formhash_provider.dart';
import '../session/forum_session_store.dart';
import 'forum_client.dart';
import 'forum_client_config.dart';
import 'forum_client_source_plan.dart';

/// Builds the currently verified Yamibo read-source matrix.
///
/// Hosts that need a different source for one business contract can assemble
/// [ForumClientSourcePlan] directly through the advanced adapters barrel.
final class YamiboForumClientBuilder {
  const YamiboForumClientBuilder({
    required this.config,
    required this.network,
    this.sessionStore,
    this.documentStore,
    this.snapshotStore,
    this.formhashProvider,
    this.resourceClient,
    this.stickerCatalogStore,
  });

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumSessionStore? sessionStore;
  final ForumDocumentStore? documentStore;
  final ForumSnapshotStore? snapshotStore;
  final ForumFormhashProvider? formhashProvider;
  final ForumResourceClient? resourceClient;
  final ForumStickerCatalogStore? stickerCatalogStore;

  YamiboForumClient buildStandardReads() {
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      sessionStore: sessionStore,
      documentStore: documentStore,
      snapshotStore: snapshotStore,
    );
    final formhash = formhashProvider;
    final forumHome = factory.createHtmlForumHome();
    return YamiboForumClient(
      config: config,
      network: network,
      resources: resourceClient,
      sourcePlan: ForumClientSourcePlan(
        forumDirectory: forumHome,
        forumHome: forumHome,
        forumTagDirectory: factory.createForumTagDirectory(),
        forumDisplay: factory.createHtmlForumDisplay(),
        favoriteForumDirectory: factory.createFavoriteForumDirectory(),
        favoriteThreadDirectory: factory.createFavoriteThreadDirectory(),
        currentUserProfile: factory.createCurrentUserProfile(),
        notifications: factory.createNotifications(),
        privateMessages: factory.createPrivateMessages(),
        stickerCatalog: factory.createStickerCatalog(
          store: stickerCatalogStore,
        ),
        forumUserProfile: factory.createForumUserProfile(),
        userBlogDirectory: factory.createUserBlogDirectory(),
        userBlogDetail: factory.createUserBlogDetail(),
        forumSearch: formhash == null
            ? null
            : factory.createForumSearch(formhash),
        comicEpisodeCatalog: factory.createApiComicEpisodeCatalog(),
        comicThreadDiscovery: factory.createApiComicThreadDiscovery(),
        threadReplyPage: factory.createApiThreadReplyPage(),
        threadDetail: factory.createHtmlThreadDetail(),
        threadIngestionDetail: factory.createApiThreadDetail(apiVersion: '4'),
        postRatings: factory.createThreadPostRatings(),
        postLocator: factory.createThreadPostLocator(),
        threadAuthorPosts: factory.createThreadAuthorPosts(),
      ),
    );
  }
}
