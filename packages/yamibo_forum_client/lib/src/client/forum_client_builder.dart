import '../adapters/forum_client_adapter_factory.dart';
import '../cache/forum_cache.dart';
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
  });

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumSessionStore? sessionStore;
  final ForumDocumentStore? documentStore;
  final ForumSnapshotStore? snapshotStore;
  final ForumFormhashProvider? formhashProvider;

  YamiboForumClient buildStandardReads() {
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      sessionStore: sessionStore,
      documentStore: documentStore,
      snapshotStore: snapshotStore,
    );
    final formhash = formhashProvider;
    return YamiboForumClient(
      config: config,
      network: network,
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
        forumSearch: formhash == null
            ? null
            : factory.createForumSearch(formhash),
        comicEpisodeCatalog: factory.createApiComicEpisodeCatalog(),
        comicThreadDiscovery: factory.createApiComicThreadDiscovery(),
        threadReplyPage: factory.createApiThreadReplyPage(),
        threadDetail: factory.createHtmlThreadDetail(),
        threadIngestionDetail: factory.createApiThreadDetail(apiVersion: '4'),
      ),
    );
  }
}
