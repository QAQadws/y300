import '../contracts/comic_contracts.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/data_command_contract.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/favorite_commands.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_home.dart';
import '../contracts/forum_authentication.dart';
import '../contracts/forum_display_models.dart';
import '../contracts/forum_display_repository.dart';
import '../contracts/forum_search.dart';
import '../contracts/forum_resource.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/message_directories.dart';
import '../contracts/sticker_catalog.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_detail_models.dart';
import '../contracts/thread_repository.dart';
import '../contracts/thread_supplemental_reads.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_transport.dart';
import '../session/forum_formhash_provider.dart';
import 'forum_client_config.dart';
import 'forum_client_source_plan.dart';

/// Source-neutral facade over the configured Yamibo forum read contracts.
///
/// A missing source never falls back to a guessed protocol. Facade methods
/// return an `unsupported` [DataReadFailure] instead.
final class YamiboForumClient {
  /// Creates a facade around an explicit, advanced source plan.
  YamiboForumClient({
    required this.config,
    required this.network,
    ForumResourceClient? resources,
    ForumFormhashProvider? formhashProvider,
    this.sourcePlan = const ForumClientSourcePlan(),
  }) : resources =
           resources ??
           (network is ForumResourceClient
               ? network as ForumResourceClient
               : const UnsupportedForumResourceClient()),
       formhashProvider =
           formhashProvider ?? const _UnsupportedForumFormhashProvider();

  /// Client origins and request configuration.
  final ForumClientConfig config;

  /// Shared structured-read transport.
  final ForumClientNetwork network;

  /// Protected image streaming client.
  final ForumResourceClient resources;

  /// Canonical formhash source shared with Host commands still being migrated.
  final ForumFormhashProvider formhashProvider;

  /// Experimental per-contract source plan used by this facade.
  final ForumClientSourcePlan sourcePlan;

  /// Configured authoritative session source, if installed.
  ForumSessionRepository? get session => sourcePlan.session;

  /// Configured password-login command, if installed.
  ForumPasswordLoginCommand? get passwordLogin => sourcePlan.passwordLogin;

  /// Configured standard-logout command, if installed.
  ForumLogoutCommand? get logout => sourcePlan.logout;

  /// Resolves the current Cookie-backed session.
  Future<ForumSessionResult> resolveSession([
    ForumSessionRequest request = const ForumSessionRequest(),
  ]) =>
      sourcePlan.session?.resolve(request) ??
      Future.value(
        const ForumSessionInconclusive(
          DataCommandFailure(
            kind: DataCommandFailureKind.unsupported,
            retryPolicy: DataCommandRetryPolicy.never,
            code: 'session_source_not_installed',
            diagnosticMessage: 'session_source_not_installed',
          ),
        ),
      );

  /// Executes password login through the configured command source.
  Future<DataCommandResult<ForumLoginReceipt>> loginWithPassword(
    ForumPasswordLoginRequest request,
  ) =>
      sourcePlan.passwordLogin?.execute(request) ??
      Future.value(const DataCommandUnsupported<ForumLoginReceipt>());

  /// Executes the configured standard logout command.
  Future<DataCommandResult<ForumLogoutReceipt>> logoutSession([
    ForumLogoutRequest request = const ForumLogoutRequest(),
  ]) =>
      sourcePlan.logout?.execute(request) ??
      Future.value(const DataCommandUnsupported<ForumLogoutReceipt>());

  /// Configured forum-directory source, if installed.
  ForumDirectoryRepository? get forumDirectory => sourcePlan.forumDirectory;

  /// Configured combined forum-home source, if installed.
  ForumHomeRepository? get forumHome => sourcePlan.forumHome;

  /// Configured forum thread-list source, if installed.
  ForumDisplayRepository? get forumDisplay => sourcePlan.forumDisplay;

  /// Configured Tag directory source, if installed.
  ForumTagDirectoryRepository? get forumTagDirectory =>
      sourcePlan.forumTagDirectory;

  /// Configured favorite-forum directory source, if installed.
  FavoriteForumDirectoryRepository? get favoriteForumDirectory =>
      sourcePlan.favoriteForumDirectory;

  /// Configured favorite-thread directory source, if installed.
  FavoriteThreadDirectoryRepository? get favoriteThreadDirectory =>
      sourcePlan.favoriteThreadDirectory;

  /// Configured forum-favorite command, if installed.
  FavoriteForumCommand? get favoriteForumCommand =>
      sourcePlan.favoriteForumCommand;

  /// Configured thread-favorite command, if installed.
  FavoriteThreadCommand? get favoriteThreadCommand =>
      sourcePlan.favoriteThreadCommand;

  /// Sets and confirms one forum's favorite state.
  Future<DataCommandResult<ForumFavoriteReceipt>> setForumFavorite(
    SetForumFavoriteRequest request,
  ) =>
      sourcePlan.favoriteForumCommand?.execute(request) ??
      Future.value(const DataCommandUnsupported<ForumFavoriteReceipt>());

  /// Sets and confirms one thread's favorite state.
  Future<DataCommandResult<ThreadFavoriteReceipt>> setThreadFavorite(
    SetThreadFavoriteRequest request,
  ) =>
      sourcePlan.favoriteThreadCommand?.execute(request) ??
      Future.value(const DataCommandUnsupported<ThreadFavoriteReceipt>());

  /// Configured current-user profile source, if installed.
  CurrentUserProfileRepository? get currentUserProfile =>
      sourcePlan.currentUserProfile;

  /// Configured public-profile source, if installed.
  ForumUserProfileRepository? get forumUserProfile =>
      sourcePlan.forumUserProfile;

  /// Configured user-blog directory source, if installed.
  UserBlogDirectoryRepository? get userBlogDirectory =>
      sourcePlan.userBlogDirectory;

  /// Configured user-blog detail source, if installed.
  UserBlogDetailRepository? get userBlogDetail => sourcePlan.userBlogDetail;

  /// Configured forum-search source, if installed.
  ForumSearchRepository? get forumSearch => sourcePlan.forumSearch;

  /// Configured presentation-oriented thread source, if installed.
  ThreadRepository? get threadDetail => sourcePlan.threadDetail;

  /// Configured structured-ingestion thread source, if installed.
  ThreadRepository? get threadIngestionDetail =>
      sourcePlan.threadIngestionDetail;

  /// Configured notification source, if installed.
  ForumNotificationRepository? get notifications => sourcePlan.notifications;

  /// Configured private-message source, if installed.
  ForumPrivateMessageRepository? get privateMessages =>
      sourcePlan.privateMessages;

  /// Configured sticker catalog source, if installed.
  ForumStickerCatalogRepository? get stickerCatalog =>
      sourcePlan.stickerCatalog;

  /// Configured complete-rating source, if installed.
  ThreadPostRatingsRepository? get postRatings => sourcePlan.postRatings;

  /// Configured post-location source, if installed.
  ThreadPostLocatorRepository? get postLocator => sourcePlan.postLocator;

  /// Configured author-filtered post source, if installed.
  ThreadAuthorPostRepository? get threadAuthorPosts =>
      sourcePlan.threadAuthorPosts;

  /// Loads the combined forum-home document.
  Future<DataReadResult<ForumHomeDocument, ForumHomeReadCapabilities>>
  loadForumHome(
    ForumHomeQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumHome?.loadHome(query, cachePolicy: cachePolicy) ??
      unsupported<ForumHomeDocument, ForumHomeReadCapabilities>();

  /// Reads the locally cached forum-home projection without networking.
  Future<ForumHomeCachedRead?> readCachedForumHome(ForumHomeQuery query) =>
      sourcePlan.forumHome?.readCached(query) ?? Future.value(null);

  /// Loads a page of forum notifications.
  Future<
    DataReadResult<ForumNotificationPage, ForumNotificationReadCapabilities>
  >
  loadNotifications(ForumNotificationQuery query) =>
      sourcePlan.notifications?.load(query) ??
      unsupported<ForumNotificationPage, ForumNotificationReadCapabilities>();

  /// Loads a page of private messages.
  Future<
    DataReadResult<ForumPrivateMessagePage, ForumPrivateMessageReadCapabilities>
  >
  loadPrivateMessages(ForumPrivateMessageQuery query) =>
      sourcePlan.privateMessages?.load(query) ??
      unsupported<
        ForumPrivateMessagePage,
        ForumPrivateMessageReadCapabilities
      >();

  /// Loads the ordered forum sticker catalog.
  Future<
    DataReadResult<ForumStickerCatalogData, ForumStickerCatalogReadCapabilities>
  >
  loadStickerCatalog(ForumStickerCatalogQuery query) =>
      sourcePlan.stickerCatalog?.load(query) ??
      unsupported<
        ForumStickerCatalogData,
        ForumStickerCatalogReadCapabilities
      >();

  /// Loads complete rating details for one post.
  Future<
    DataReadResult<ThreadPostRatingsData, ThreadPostRatingsReadCapabilities>
  >
  loadPostRatings(ThreadPostRatingsQuery query) =>
      sourcePlan.postRatings?.load(query) ??
      unsupported<ThreadPostRatingsData, ThreadPostRatingsReadCapabilities>();

  /// Resolves the exact page containing a post.
  Future<
    DataReadResult<ThreadPostLocationData, ThreadPostLocatorReadCapabilities>
  >
  locatePost(ThreadPostLocationQuery query) =>
      sourcePlan.postLocator?.locate(query) ??
      unsupported<ThreadPostLocationData, ThreadPostLocatorReadCapabilities>();

  /// Loads a page containing only posts by the requested author.
  Future<DataReadResult<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>>
  loadAuthorPosts(ThreadAuthorPostQuery query) =>
      sourcePlan.threadAuthorPosts?.load(query) ??
      unsupported<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>();

  /// Loads the forum hierarchy using the selected cache policy.
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  loadForumDirectory(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumDirectory?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumDirectoryData, ForumDirectoryReadCapabilities>();

  /// Loads the Tag directory using the selected cache policy.
  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  loadForumTagDirectory(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumTagDirectory?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>();

  /// Loads the authenticated user's favorite forums.
  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  loadFavoriteForums(
    FavoriteForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.favoriteForumDirectory?.load(
        query,
        cachePolicy: cachePolicy,
      ) ??
      unsupported<
        FavoriteForumDirectoryData,
        FavoriteForumDirectoryReadCapabilities
      >();

  /// Loads the authenticated user's favorite threads.
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  loadFavoriteThreads(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.favoriteThreadDirectory?.load(
        query,
        cachePolicy: cachePolicy,
      ) ??
      unsupported<
        FavoriteThreadDirectoryData,
        FavoriteThreadDirectoryReadCapabilities
      >();

  /// Loads the authenticated user's source-neutral profile projection.
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  loadCurrentUserProfile(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.currentUserProfile?.load(query, cachePolicy: cachePolicy) ??
      unsupported<CurrentUserProfileData, CurrentUserProfileReadCapabilities>();

  /// Loads a public forum profile.
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  loadForumUserProfile(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumUserProfile?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumUserProfileData, ForumUserProfileReadCapabilities>();

  /// Loads a user's blog directory.
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  loadUserBlogs(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.userBlogDirectory?.load(query, cachePolicy: cachePolicy) ??
      unsupported<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>();

  /// Loads one user blog entry.
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  loadUserBlogDetail(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.userBlogDetail?.load(query, cachePolicy: cachePolicy) ??
      unsupported<UserBlogDetailData, UserBlogDetailReadCapabilities>();

  /// Starts a forum search.
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  searchForums(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumSearch?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumSearchData, ForumSearchReadCapabilities>();

  /// Loads a previously proved next search-result page.
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextForumSearchPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumSearch?.loadNextPage(
        query,
        page,
        cachePolicy: cachePolicy,
      ) ??
      unsupported<ForumSearchData, ForumSearchReadCapabilities>();

  /// Produces the standard fail-closed result for an uninstalled source.
  Future<DataReadResult<T, C>> unsupported<T, C>() async =>
      DataReadFailure<T, C>(
        kind: DataReadFailureKind.unsupported,
        code: 'source_not_installed',
        diagnosticMessage: 'source_not_installed',
      );

  /// Loads a forum thread listing.
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  loadForumDisplay(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumDisplay?.getForumDisplayByQuery(
        query,
        cachePolicy: cachePolicy,
      ) ??
      unsupported<ForumDisplayData, ForumDisplayReadCapabilities>();

  /// Loads one page of a thread detail.
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  loadThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) =>
      sourcePlan.threadDetail?.getThreadDetail(
        tid: tid,
        page: page,
        query: query,
      ) ??
      unsupported<ThreadDetailData, ThreadDetailReadCapabilities>();

  /// Configured comic episode image catalog source, if installed.
  ComicEpisodeCatalogRepository? get comicEpisodeCatalog =>
      sourcePlan.comicEpisodeCatalog;

  /// Configured comic discovery source, if installed.
  ComicThreadDiscoveryRepository? get comicThreadDiscovery =>
      sourcePlan.comicThreadDiscovery;

  /// Configured thread-reply page source, if installed.
  ThreadReplyPageRepository? get threadReplyPage => sourcePlan.threadReplyPage;

  /// Loads the ordered image catalog for one comic episode.
  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  >
  loadComicEpisodeCatalog(ComicEpisodeCatalogRequest request) =>
      sourcePlan.comicEpisodeCatalog?.loadCatalog(request) ??
      unsupported<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>();

  /// Loads a source-neutral comic discovery document.
  Future<
    DataReadResult<
      ComicThreadDiscoveryDocument,
      ComicThreadDiscoveryCapabilities
    >
  >
  loadComicThreadDiscovery(ComicThreadDiscoveryRequest request) =>
      sourcePlan.comicThreadDiscovery?.load(request) ??
      unsupported<
        ComicThreadDiscoveryDocument,
        ComicThreadDiscoveryCapabilities
      >();

  /// Loads a page of thread replies.
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadThreadReplies({required String tid, required int page}) =>
      sourcePlan.threadReplyPage?.loadPage(tid: tid, page: page) ??
      unsupported<ThreadReplyPage, ThreadReplyPageReadCapabilities>();
}

final class _UnsupportedForumFormhashProvider implements ForumFormhashProvider {
  const _UnsupportedForumFormhashProvider();

  @override
  Future<ForumFormhashResult> loadFormhash({
    bool preferProfile = true,
    ForumRequestCancellation? cancellation,
  }) async => const ForumFormhashError(
    ForumTransportFailure(
      kind: ForumTransportFailureKind.business,
      code: 'formhash_source_not_installed',
    ),
  );
}
