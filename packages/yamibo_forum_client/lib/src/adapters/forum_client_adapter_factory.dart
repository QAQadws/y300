import '../client/forum_client_config.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/favorite_commands.dart';
import '../contracts/forum_authentication.dart';
import '../contracts/forum_image_attachments.dart';
import '../contracts/comic_contracts.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_display_repository.dart';
import '../contracts/forum_home.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/forum_search.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/message_directories.dart';
import '../contracts/sticker_catalog.dart';
import '../contracts/thread_repository.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_composer_commands.dart';
import '../contracts/thread_interaction_commands.dart';
import '../contracts/thread_poll_vote_command.dart';
import '../contracts/thread_post_edit.dart';
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

/// Creates the concrete Discuz sources used by the standard client.
///
/// Methods expose source-neutral contract types. Multi-role adapters are
/// returned as named records so callers never need to depend on a concrete
/// Discuz implementation class.
final class ForumClientAdapterFactory {
  /// Creates an adapter factory around Host transport and persistence ports.
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

  /// Forum origins and request identities used by every adapter.
  final ForumClientConfig config;

  /// Shared Host transport used by every adapter.
  final ForumClientNetwork network;

  /// Request profiles.
  final ForumRequestProfileResolver requestProfiles;
  final DiscuzApiClient _api;

  /// Optional reproducible session projection store.
  final ForumSessionStore? sessionStore;

  /// Optional persistent Cookie store required by authentication commands.
  final ForumCookieStore? cookieStore;

  /// Optional source-document cache.
  final ForumDocumentStore? documentStore;

  /// Optional parsed-snapshot cache.
  final ForumSnapshotStore? snapshotStore;

  /// Creates the Discuz API forum-directory source.
  ForumDirectoryRepository createApiForumDirectory() =>
      DiscuzForumDirectoryRepository(_api);

  /// Creates the mobile HTML forum-directory source.
  ForumDirectoryRepository createHtmlForumDirectory() =>
      DiscuzForumDirectoryHtmlRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
        sessionStore: sessionStore,
        documentStore: documentStore,
        snapshotStore: snapshotStore,
      );

  /// Creates one shared HTML source for home and forum-directory reads.
  ({ForumHomeRepository home, ForumDirectoryRepository directory})
  createHtmlForumHome() {
    final adapter = DiscuzForumHomeHtmlRepository(
      config: config,
      network: network,
      requestProfiles: requestProfiles,
      sessionStore: sessionStore,
      documentStore: documentStore,
      snapshotStore: snapshotStore,
    );
    return (home: adapter, directory: adapter);
  }

  /// Creates the Discuz notification directory source.
  ForumNotificationRepository createNotifications() =>
      DiscuzForumNotificationRepository(_api);

  /// Creates the Discuz private-message directory source.
  ForumPrivateMessageRepository createPrivateMessages() =>
      DiscuzForumPrivateMessageRepository(_api);

  /// Creates the sticker source, optionally backed by [store].
  ForumStickerCatalogRepository createStickerCatalog({
    ForumStickerCatalogStore? store,
  }) => DiscuzForumStickerCatalogRepository(
    api: _api,
    config: config,
    store: store,
  );

  /// Creates the AJAX source for complete post-rating details.
  ThreadPostRatingsRepository createThreadPostRatings() =>
      DiscuzThreadPostRatingsRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  /// Creates a shared preparation/command pair for post ratings.
  ({
    ThreadPostRatingPreparationRepository preparation,
    ThreadPostRatingCommand command,
  })
  createThreadPostRatingInteraction() {
    final adapter = DiscuzThreadPostRatingAdapter(
      config: config,
      network: network,
      requestProfiles: requestProfiles,
    );
    return (preparation: adapter, command: adapter);
  }

  /// Creates a shared preparation/command pair for post comments.
  ({
    ThreadPostCommentPreparationRepository preparation,
    ThreadPostCommentCommand command,
  })
  createThreadPostCommentInteraction() {
    final adapter = DiscuzThreadPostCommentAdapter(
      config: config,
      network: network,
      requestProfiles: requestProfiles,
    );
    return (preparation: adapter, command: adapter);
  }

  /// Creates the source-neutral poll-vote command.
  ThreadPollVoteCommand createThreadPollVote(ForumFormhashProvider formhash) =>
      DiscuzThreadPollVoteCommand(
        api: _api,
        config: config,
        formhash: formhash,
      );

  /// Creates a shared preparation/command pair for thread creation.
  ({
    ThreadCreationPreparationRepository preparation,
    ThreadCreationCommand command,
  })
  createThreadCreation(ForumFormhashProvider formhash) {
    final adapter = DiscuzThreadCreationAdapter(
      api: _api,
      config: config,
      formhashProvider: formhash,
    );
    return (preparation: adapter, command: adapter);
  }

  /// Creates a shared preparation/command pair for replies.
  ({ThreadReplyPreparationRepository preparation, ThreadReplyCommand command})
  createThreadReply(ForumFormhashProvider formhash) {
    final adapter = DiscuzThreadReplyAdapter(
      api: _api,
      config: config,
      network: network,
      requestProfiles: requestProfiles,
      formhashProvider: formhash,
    );
    return (preparation: adapter, command: adapter);
  }

  /// Creates a shared preparation/command pair for ordinary post edits.
  ({
    ThreadPostEditPreparationRepository preparation,
    ThreadPostEditCommand command,
  })
  createThreadPostEdit() {
    final adapter = DiscuzThreadPostEditAdapter(
      config: config,
      network: network,
      requestProfiles: requestProfiles,
    );
    return (preparation: adapter, command: adapter);
  }

  /// Creates a shared preparation/command pair for image uploads.
  ({
    ForumImageAttachmentUploadPreparationRepository preparation,
    ForumImageAttachmentUploadCommand command,
  })
  createImageAttachmentUpload(ForumMultipartClient? multipart) {
    final adapter = DiscuzImageAttachmentUploadAdapter(
      _api,
      config,
      multipart,
      sessionStore,
      requestProfiles,
    );
    return (preparation: adapter, command: adapter);
  }

  /// Creates a shared directory/delete pair for unused images.
  ({
    ForumUnusedImageAttachmentDirectoryRepository directory,
    ForumUnusedImageAttachmentDeleteCommand delete,
  })
  createUnusedImageAttachments(ForumFormhashProvider formhash) {
    final adapter = DiscuzUnusedImageAttachmentAdapter(
      config,
      network,
      requestProfiles,
      sessionStore,
      formhash,
    );
    return (directory: adapter, delete: adapter);
  }

  /// Creates the command for deleting an image attached to an existing post.
  ForumPostImageAttachmentDeleteCommand createPostImageAttachmentDelete(
    ForumFormhashProvider formhash,
  ) => DiscuzPostImageAttachmentDeleteAdapter(
    config: config,
    network: network,
    requestProfiles: requestProfiles,
    formhash: formhash,
  );

  /// Creates the same-site redirect source for locating a post page.
  ThreadPostLocatorRepository createThreadPostLocator() =>
      DiscuzThreadPostLocatorRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  /// Creates the fixed-version-1 author-post source used by novel ingestion.
  ThreadAuthorPostRepository createThreadAuthorPosts() =>
      DiscuzThreadAuthorPostRepository(_api);

  /// Creates the desktop HTML Tag directory source.
  ForumTagDirectoryRepository createForumTagDirectory() =>
      DiscuzForumTagDirectoryRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  /// Creates the Discuz forum-favorite directory source.
  FavoriteForumDirectoryRepository createFavoriteForumDirectory() =>
      DiscuzFavoriteForumDirectoryRepository(_api);

  /// Creates the Discuz thread-favorite directory source.
  FavoriteThreadDirectoryRepository createFavoriteThreadDirectory() =>
      DiscuzFavoriteThreadDirectoryRepository(_api);

  /// Creates the target-state command for forum favorites.
  FavoriteForumCommand createFavoriteForumCommand({
    required ForumFormhashProvider formhash,
    required FavoriteForumDirectoryRepository directory,
  }) => DiscuzFavoriteForumCommandAdapter(_api, formhash, directory);

  /// Creates the target-state command for thread favorites.
  FavoriteThreadCommand createFavoriteThreadCommand({
    required ForumFormhashProvider formhash,
    required FavoriteThreadDirectoryRepository directory,
  }) => DiscuzFavoriteThreadCommandAdapter(_api, formhash, directory);

  /// Creates the current authenticated user profile source.
  CurrentUserProfileRepository createCurrentUserProfile() =>
      DiscuzCurrentUserProfileRepository(_api);

  /// Creates the public user-profile HTML source.
  ForumUserProfileRepository createForumUserProfile() =>
      DiscuzForumUserProfileRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  /// Creates the user-blog directory HTML source.
  UserBlogDirectoryRepository createUserBlogDirectory() =>
      DiscuzUserBlogDirectoryRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  /// Creates the user-blog detail HTML source.
  UserBlogDetailRepository createUserBlogDetail() =>
      DiscuzUserBlogDetailRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      );

  /// Creates the formhash-backed forum-search source.
  ForumSearchRepository createForumSearch(ForumFormhashProvider formhash) =>
      DiscuzForumSearchRepository(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
        formhashProvider: formhash,
      );

  /// Creates the canonical formhash provider backed by [sessions].
  ForumFormhashProvider createStandardFormhashProvider(
    ForumSessionStore sessions,
  ) => SessionForumFormhashProvider(
    sessions: sessions,
    loadFromProfile: (cancellation) =>
        _loadFormhash('profile', cancellation: cancellation),
    loadFallback: (cancellation) =>
        _loadFormhash('forumindex', cancellation: cancellation),
  );

  /// Creates shared session, login, and logout authentication contracts.
  ({
    ForumSessionRepository session,
    ForumPasswordLoginCommand login,
    ForumLogoutCommand logout,
  })
  createAuthentication(
    ForumFormhashProvider formhash,
    ForumSessionStore sessions,
  ) {
    final adapter = DiscuzAuthenticationAdapter(
      DiscuzApiClient(
        config: config,
        network: network,
        requestProfiles: requestProfiles,
      ),
      formhash,
      sessions,
      cookieStore,
    );
    return (
      session: adapter,
      login: adapter,
      logout: DiscuzLogoutCommandAdapter(adapter),
    );
  }

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

  /// Creates the HTML-first forum-display source with configured fallbacks.
  ForumDisplayRepository createHtmlForumDisplay() => ForumDisplayHtmlRepository(
    config: config,
    network: network,
    requestProfiles: requestProfiles,
    sessionStore: sessionStore,
    documentStore: documentStore,
    snapshotStore: snapshotStore,
  );

  /// Creates the Discuz API forum-display source.
  ForumDisplayRepository createApiForumDisplay() =>
      DiscuzForumDisplayRepository(_api);

  /// Creates the HTML-first thread-detail source with configured fallbacks.
  ThreadRepository createHtmlThreadDetail() => ThreadDetailHtmlRepository(
    config: config,
    network: network,
    requestProfiles: requestProfiles,
    documentStore: documentStore,
    snapshotStore: snapshotStore,
  );

  /// Creates a Discuz thread source fixed to [apiVersion].
  ThreadRepository createApiThreadDetail({String apiVersion = '4'}) =>
      ApiThreadRepository(_api, apiVersion: apiVersion);

  /// Creates the v4-backed comic episode image catalog source.
  ComicEpisodeCatalogRepository createApiComicEpisodeCatalog() =>
      DiscuzApiComicEpisodeCatalogRepository(
        threadRepository: createApiThreadDetail(),
        config: config,
      );

  /// Creates the v4-backed comic thread discovery source.
  ComicThreadDiscoveryRepository createApiComicThreadDiscovery() =>
      ThreadRepositoryComicThreadDiscoveryAdapter(
        threadRepository: createApiThreadDetail(),
        config: config,
      );

  /// Creates the v4-backed thread reply-page source.
  ThreadReplyPageRepository createApiThreadReplyPage() =>
      ApiThreadReplyPageRepository(repository: createApiThreadDetail());
}
