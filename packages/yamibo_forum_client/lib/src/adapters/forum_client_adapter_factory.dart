import '../client/forum_client_config.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/favorite_commands.dart';
import '../contracts/forum_authentication.dart';
import '../contracts/forum_image_attachments.dart';
import '../contracts/comic_contracts.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_display_repository.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/forum_search.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/message_directories.dart';
import '../contracts/sticker_catalog.dart';
import '../contracts/thread_repository.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_poll_vote_command.dart';
import '../contracts/thread_supplemental_reads.dart';
import '../network/forum_network.dart';
import '../network/forum_multipart.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import '../cache/forum_cache.dart';
import '../session/forum_session_store.dart';
import '../session/forum_cookie_store.dart';
import 'discuz_authentication_adapter.dart';
import 'discuz_image_attachment_adapters.dart';
import 'discuz_api_client.dart';
import 'discuz_comic_read_adapters.dart';
import 'discuz_directory_adapters.dart';
import 'discuz_favorite_commands.dart';
import 'discuz_forum_tag_directory_repository.dart';
import 'discuz_forum_directory_html_repository.dart';
import 'discuz_forum_home_html_repository.dart';
import 'discuz_forum_search_repository.dart';
import 'discuz_forum_display_repositories.dart';
import 'discuz_profile_html_adapters.dart';
import 'discuz_thread_repositories.dart';
import 'discuz_thread_interaction_commands.dart';
import 'discuz_thread_poll_vote_command.dart';
import 'discuz_thread_composer_commands.dart';
import 'discuz_thread_post_edit_adapter.dart';
import 'discuz_supplemental_read_adapters.dart';
import '../session/forum_formhash_provider.dart';

final class ForumClientAdapterFactory {
  ForumClientAdapterFactory({
    required this.config,
    required this.network,
    ForumRequestProfileResolver? requestProfiles,
    this.sessionStore,
    this.cookieStore,
    this.documentStore,
    this.snapshotStore,
  }) : requestProfiles =
           requestProfiles ?? DefaultForumRequestProfileResolver(config),
       _api = DiscuzApiClient(
         config: config,
         network: network,
         requestProfiles:
             requestProfiles ?? DefaultForumRequestProfileResolver(config),
         sessionStore: sessionStore,
       );

  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final DiscuzApiClient _api;
  final ForumSessionStore? sessionStore;
  final ForumCookieStore? cookieStore;
  final ForumDocumentStore? documentStore;
  final ForumSnapshotStore? snapshotStore;

  ForumDirectoryRepository createApiForumDirectory() =>
      DiscuzForumDirectoryRepository(_api);

  ForumDirectoryRepository createHtmlForumDirectory() =>
      DiscuzForumDirectoryHtmlRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
        sessionStore: sessionStore,
        documentStore: documentStore,
        snapshotStore: snapshotStore,
      );

  DiscuzForumHomeHtmlRepository createHtmlForumHome() =>
      DiscuzForumHomeHtmlRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
        sessionStore: sessionStore,
        documentStore: documentStore,
        snapshotStore: snapshotStore,
      );

  ForumNotificationRepository createNotifications() =>
      DiscuzForumNotificationRepository(_api);

  ForumPrivateMessageRepository createPrivateMessages() =>
      DiscuzForumPrivateMessageRepository(_api);

  ForumStickerCatalogRepository createStickerCatalog({
    ForumStickerCatalogStore? store,
  }) => DiscuzForumStickerCatalogRepository(
    api: _api,
    config: config,
    store: store,
  );

  ThreadPostRatingsRepository createThreadPostRatings() =>
      DiscuzThreadPostRatingsRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  DiscuzThreadPostRatingAdapter createThreadPostRatingInteraction() =>
      DiscuzThreadPostRatingAdapter(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  DiscuzThreadPostCommentAdapter createThreadPostCommentInteraction() =>
      DiscuzThreadPostCommentAdapter(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  ThreadPollVoteCommand createThreadPollVote(ForumFormhashProvider formhash) =>
      DiscuzThreadPollVoteCommand(
        api: _api,
        config: config,
        formhash: formhash,
      );

  DiscuzThreadCreationAdapter createThreadCreation(
    ForumFormhashProvider formhash,
  ) => DiscuzThreadCreationAdapter(
    api: _api,
    config: config,
    formhashProvider: formhash,
  );

  DiscuzThreadReplyAdapter createThreadReply(ForumFormhashProvider formhash) =>
      DiscuzThreadReplyAdapter(
        api: _api,
        config: config,
        network: network,
        requestProfiles: requestProfiles,
        formhashProvider: formhash,
      );

  DiscuzThreadPostEditAdapter createThreadPostEdit() =>
      DiscuzThreadPostEditAdapter(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  DiscuzImageAttachmentUploadAdapter createImageAttachmentUpload(
    ForumMultipartClient? multipart,
  ) => DiscuzImageAttachmentUploadAdapter(
    _api,
    config,
    multipart,
    sessionStore,
    requestProfiles,
  );

  DiscuzUnusedImageAttachmentAdapter createUnusedImageAttachments(
    ForumFormhashProvider formhash,
  ) => DiscuzUnusedImageAttachmentAdapter(
    config,
    network,
    requestProfiles,
    sessionStore,
    formhash,
  );

  ForumPostImageAttachmentDeleteCommand createPostImageAttachmentDelete(
    ForumFormhashProvider formhash,
  ) => DiscuzPostImageAttachmentDeleteAdapter(
    config: config,
    network: network,
    requestProfiles: requestProfiles,
    formhash: formhash,
  );

  ThreadPostLocatorRepository createThreadPostLocator() =>
      DiscuzThreadPostLocatorRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  ThreadAuthorPostRepository createThreadAuthorPosts() =>
      DiscuzThreadAuthorPostRepository(_api);

  ForumTagDirectoryRepository createForumTagDirectory() =>
      DiscuzForumTagDirectoryRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  FavoriteForumDirectoryRepository createFavoriteForumDirectory() =>
      DiscuzFavoriteForumDirectoryRepository(_api);

  FavoriteThreadDirectoryRepository createFavoriteThreadDirectory() =>
      DiscuzFavoriteThreadDirectoryRepository(_api);

  FavoriteForumCommand createFavoriteForumCommand({
    required ForumFormhashProvider formhash,
    required FavoriteForumDirectoryRepository directory,
  }) => DiscuzFavoriteForumCommandAdapter(_api, formhash, directory);

  FavoriteThreadCommand createFavoriteThreadCommand({
    required ForumFormhashProvider formhash,
    required FavoriteThreadDirectoryRepository directory,
  }) => DiscuzFavoriteThreadCommandAdapter(_api, formhash, directory);

  CurrentUserProfileRepository createCurrentUserProfile() =>
      DiscuzCurrentUserProfileRepository(_api);

  ForumUserProfileRepository createForumUserProfile() =>
      DiscuzForumUserProfileRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  UserBlogDirectoryRepository createUserBlogDirectory() =>
      DiscuzUserBlogDirectoryRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  UserBlogDetailRepository createUserBlogDetail() =>
      DiscuzUserBlogDetailRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  ForumSearchRepository createForumSearch(ForumFormhashProvider formhash) =>
      DiscuzForumSearchRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
        formhashProvider: formhash,
      );

  ForumFormhashProvider createStandardFormhashProvider(
    ForumSessionStore sessions,
  ) => SessionForumFormhashProvider(
    sessions: sessions,
    loadFromProfile: (cancellation) =>
        _loadFormhash('profile', cancellation: cancellation),
    loadFallback: (cancellation) =>
        _loadFormhash('forumindex', cancellation: cancellation),
  );

  DiscuzAuthenticationAdapter createAuthentication(
    ForumFormhashProvider formhash,
    ForumSessionStore sessions,
  ) => DiscuzAuthenticationAdapter(
    DiscuzApiClient(
      config: config,
      network: network,
      requestProfiles: requestProfiles,
    ),
    formhash,
    sessions,
    cookieStore,
  );

  ForumLogoutCommand createLogoutCommand(
    DiscuzAuthenticationAdapter authentication,
  ) => DiscuzLogoutCommandAdapter(authentication);

  Future<ForumFormhashResult> _loadFormhash(
    String module, {
    ForumRequestCancellation? cancellation,
  }) async {
    final result = await _api.get(module: module, cancellation: cancellation);
    return switch (result) {
      ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(:final failure) =>
        ForumFormhashError(failure),
      ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>(
        :final response,
      ) =>
        switch (response.body.variables['formhash']?.toString().trim()) {
          final String value when value.isNotEmpty => ForumFormhashSuccess(
            value,
          ),
          _ => const ForumFormhashError(
            ForumTransportFailure(
              kind: ForumTransportFailureKind.business,
              code: 'formhash_unavailable',
            ),
          ),
        },
    };
  }

  ForumDisplayRepository createHtmlForumDisplay() => ForumDisplayHtmlRepository(
    config: config,
    network: network,
    requestProfiles: requestProfiles,
    sessionStore: sessionStore,
    documentStore: documentStore,
    snapshotStore: snapshotStore,
  );

  ForumDisplayRepository createApiForumDisplay() =>
      DiscuzForumDisplayRepository(_api);

  ThreadRepository createHtmlThreadDetail() => ThreadDetailHtmlRepository(
    config: config,
    network: network,
    requestProfiles: requestProfiles,
    documentStore: documentStore,
    snapshotStore: snapshotStore,
  );

  ThreadRepository createApiThreadDetail({String apiVersion = '4'}) =>
      ApiThreadRepository(_api, apiVersion: apiVersion);

  ComicEpisodeCatalogRepository createApiComicEpisodeCatalog() =>
      DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: createApiThreadDetail(),
        config: config,
      );

  ComicThreadDiscoveryRepository createApiComicThreadDiscovery() =>
      ThreadRepositoryComicThreadDiscoveryAdapter(
        threadRepository: createApiThreadDetail(),
        config: config,
      );

  ThreadReplyPageRepository createApiThreadReplyPage() =>
      ApiThreadReplyPageRepository(repository: createApiThreadDetail());
}
