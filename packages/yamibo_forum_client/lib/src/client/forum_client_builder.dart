import '../adapters/forum_client_adapter_factory.dart';
import '../cache/forum_cache.dart';
import '../contracts/forum_resource.dart';
import '../contracts/sticker_catalog.dart';
import '../logging/forum_client_logger.dart';
import '../network/dio_forum_network.dart';
import '../network/forum_network.dart';
import '../network/forum_multipart.dart';
import '../session/forum_cookie_store.dart';
import '../session/forum_formhash_provider.dart';
import '../session/forum_session_store.dart';
import '../waf/forum_waf.dart';
import 'forum_client.dart';
import 'forum_client_cache_ports.dart';
import 'forum_client_config.dart';
import 'forum_client_source_plan.dart';

/// Builds the currently verified Yamibo read-source matrix.
///
/// Hosts that need a different source for one business contract can assemble
/// [ForumClientSourcePlan] directly through the advanced adapters barrel.
final class YamiboForumClientBuilder {
  /// Creates a builder around a host-supplied transport.
  ///
  /// This is the integration point used by Y300 to keep package reads on its
  /// process-wide Cookie, session, and WAF transport. Third-party clients that
  /// do not already own a transport should prefer [standardDio].
  const YamiboForumClientBuilder({
    required this.config,
    required this.network,
    this.sessionStore,
    this.documentStore,
    this.snapshotStore,
    this.formhashProvider,
    this.cookieStore,
    this.resourceClient,
    this.multipartClient,
    this.stickerCatalogStore,
  });

  /// Creates the standard pure-Dart Dio runtime.
  ///
  /// A production host only needs to supply persistent Cookie and cache ports.
  /// Supplying [waf] enables verified recovery when the managed forum returns
  /// HTTP 405; without it, challenged requests fail closed as unavailable.
  factory YamiboForumClientBuilder.standardDio({
    required ForumClientConfig config,
    required ForumCookieStore cookies,
    required ForumClientCachePorts caches,
    ForumWafRecoveryDelegate? waf,
    ForumClientLogger? logger,
  }) {
    final network = DioForumClientNetwork(
      config: config,
      cookies: cookies,
      waf: waf,
      logger: logger,
    );
    return YamiboForumClientBuilder(
      config: config,
      network: network,
      sessionStore: MemoryForumSessionStore(),
      documentStore: caches.documents,
      snapshotStore: caches.snapshots,
      resourceClient: network,
      multipartClient: network,
      cookieStore: cookies,
      stickerCatalogStore: caches.stickers,
    );
  }

  /// Forum origins, request identities, and timeout configuration.
  final ForumClientConfig config;

  /// Transport shared by every structured read adapter.
  final ForumClientNetwork network;

  /// Optional host session projection; an in-memory store is used by default.
  final ForumSessionStore? sessionStore;

  /// Optional source-document cache.
  final ForumDocumentStore? documentStore;

  /// Optional parsed-snapshot cache.
  final ForumSnapshotStore? snapshotStore;

  /// Optional formhash override used by hosts with an existing session stack.
  final ForumFormhashProvider? formhashProvider;

  /// Optional persistent Cookie port required by authentication commands.
  final ForumCookieStore? cookieStore;

  /// Optional protected-resource transport override.
  final ForumResourceClient? resourceClient;

  /// Optional streamed multipart transport used by attachment commands.
  final ForumMultipartClient? multipartClient;

  /// Optional persistent sticker catalog store.
  final ForumStickerCatalogStore? stickerCatalogStore;

  /// Builds the currently verified read and basic-authentication matrix.
  YamiboForumClient buildStandardClient() {
    final sessions = sessionStore ?? MemoryForumSessionStore();
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      sessionStore: sessions,
      documentStore: documentStore,
      snapshotStore: snapshotStore,
      cookieStore: cookieStore,
    );
    final formhash =
        formhashProvider ?? factory.createStandardFormhashProvider(sessions);
    final forumHome = factory.createHtmlForumHome();
    final authentication = factory.createAuthentication(formhash, sessions);
    final favoriteForumDirectory = factory.createFavoriteForumDirectory();
    final favoriteThreadDirectory = factory.createFavoriteThreadDirectory();
    final postRating = factory.createThreadPostRatingInteraction();
    final postComment = factory.createThreadPostCommentInteraction();
    final threadCreation = factory.createThreadCreation(formhash);
    final threadReply = factory.createThreadReply(formhash);
    final imageUpload = factory.createImageAttachmentUpload(
      multipartClient ??
          (network is ForumMultipartClient
              ? network as ForumMultipartClient
              : null),
    );
    final unusedImages = factory.createUnusedImageAttachments(formhash);
    return YamiboForumClient(
      config: config,
      network: network,
      resources: resourceClient,
      multipart: multipartClient,
      formhashProvider: formhash,
      sourcePlan: ForumClientSourcePlan(
        forumDirectory: forumHome,
        forumHome: forumHome,
        forumTagDirectory: factory.createForumTagDirectory(),
        forumDisplay: factory.createHtmlForumDisplay(),
        favoriteForumDirectory: favoriteForumDirectory,
        favoriteThreadDirectory: favoriteThreadDirectory,
        favoriteForumCommand: factory.createFavoriteForumCommand(
          formhash: formhash,
          directory: favoriteForumDirectory,
        ),
        favoriteThreadCommand: factory.createFavoriteThreadCommand(
          formhash: formhash,
          directory: favoriteThreadDirectory,
        ),
        currentUserProfile: factory.createCurrentUserProfile(),
        notifications: factory.createNotifications(),
        privateMessages: factory.createPrivateMessages(),
        stickerCatalog: factory.createStickerCatalog(
          store: stickerCatalogStore,
        ),
        forumUserProfile: factory.createForumUserProfile(),
        userBlogDirectory: factory.createUserBlogDirectory(),
        userBlogDetail: factory.createUserBlogDetail(),
        forumSearch: factory.createForumSearch(formhash),
        comicEpisodeCatalog: factory.createApiComicEpisodeCatalog(),
        comicThreadDiscovery: factory.createApiComicThreadDiscovery(),
        threadReplyPage: factory.createApiThreadReplyPage(),
        threadDetail: factory.createHtmlThreadDetail(),
        threadIngestionDetail: factory.createApiThreadDetail(apiVersion: '4'),
        postRatingPreparation: postRating,
        postRatingCommand: postRating,
        postCommentPreparation: postComment,
        postCommentCommand: postComment,
        threadCreationPreparation: threadCreation,
        threadCreationCommand: threadCreation,
        threadReplyPreparation: threadReply,
        threadReplyCommand: threadReply,
        imageAttachmentUploadPreparation: imageUpload,
        imageAttachmentUploadCommand: imageUpload,
        unusedImageAttachments: unusedImages,
        unusedImageAttachmentDelete: unusedImages,
        postImageAttachmentDelete: factory.createPostImageAttachmentDelete(
          formhash,
        ),
        postRatings: factory.createThreadPostRatings(),
        postLocator: factory.createThreadPostLocator(),
        threadAuthorPosts: factory.createThreadAuthorPosts(),
        session: authentication,
        passwordLogin: authentication,
        logout: factory.createLogoutCommand(authentication),
      ),
    );
  }

  /// Builds the standard client.
  ///
  /// Deprecated because the standard matrix now also contains basic
  /// authentication commands. Existing integrations remain source-compatible.
  @Deprecated('Use buildStandardClient() instead.')
  YamiboForumClient buildStandardReads() => buildStandardClient();
}
