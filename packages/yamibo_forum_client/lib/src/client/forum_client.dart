import '../contracts/comic_contracts.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_display_models.dart';
import '../contracts/forum_display_repository.dart';
import '../contracts/forum_search.dart';
import '../contracts/forum_resource.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_detail_models.dart';
import '../contracts/thread_repository.dart';
import '../network/forum_network.dart';
import 'forum_client_config.dart';
import 'forum_client_source_plan.dart';

final class YamiboForumClient {
  YamiboForumClient({
    required this.config,
    required this.network,
    ForumResourceClient? resources,
    this.sourcePlan = const ForumClientSourcePlan(),
  }) : resources =
           resources ??
           (network is ForumResourceClient
               ? network as ForumResourceClient
               : const UnsupportedForumResourceClient());
  final ForumClientConfig config;
  final ForumClientNetwork network;
  final ForumResourceClient resources;
  final ForumClientSourcePlan sourcePlan;

  ForumDirectoryRepository? get forumDirectory => sourcePlan.forumDirectory;
  ForumDisplayRepository? get forumDisplay => sourcePlan.forumDisplay;
  ForumTagDirectoryRepository? get forumTagDirectory =>
      sourcePlan.forumTagDirectory;
  FavoriteForumDirectoryRepository? get favoriteForumDirectory =>
      sourcePlan.favoriteForumDirectory;
  FavoriteThreadDirectoryRepository? get favoriteThreadDirectory =>
      sourcePlan.favoriteThreadDirectory;
  CurrentUserProfileRepository? get currentUserProfile =>
      sourcePlan.currentUserProfile;
  ForumUserProfileRepository? get forumUserProfile =>
      sourcePlan.forumUserProfile;
  UserBlogDirectoryRepository? get userBlogDirectory =>
      sourcePlan.userBlogDirectory;
  UserBlogDetailRepository? get userBlogDetail => sourcePlan.userBlogDetail;
  ForumSearchRepository? get forumSearch => sourcePlan.forumSearch;
  ThreadRepository? get threadDetail => sourcePlan.threadDetail;
  ThreadRepository? get threadIngestionDetail =>
      sourcePlan.threadIngestionDetail;

  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  loadForumDirectory(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumDirectory?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumDirectoryData, ForumDirectoryReadCapabilities>();

  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  loadForumTagDirectory(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumTagDirectory?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>();

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

  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  loadCurrentUserProfile(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.currentUserProfile?.load(query, cachePolicy: cachePolicy) ??
      unsupported<CurrentUserProfileData, CurrentUserProfileReadCapabilities>();

  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  loadForumUserProfile(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumUserProfile?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumUserProfileData, ForumUserProfileReadCapabilities>();

  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  loadUserBlogs(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.userBlogDirectory?.load(query, cachePolicy: cachePolicy) ??
      unsupported<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>();

  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  loadUserBlogDetail(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.userBlogDetail?.load(query, cachePolicy: cachePolicy) ??
      unsupported<UserBlogDetailData, UserBlogDetailReadCapabilities>();

  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  searchForums(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) =>
      sourcePlan.forumSearch?.load(query, cachePolicy: cachePolicy) ??
      unsupported<ForumSearchData, ForumSearchReadCapabilities>();

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

  Future<DataReadResult<T, C>> unsupported<T, C>() async =>
      DataReadFailure<T, C>(
        kind: DataReadFailureKind.unsupported,
        code: 'source_not_installed',
        diagnosticMessage: 'source_not_installed',
      );

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

  // Keep the narrow phase-2 types visible to the package API without creating
  // a second transport-specific repository abstraction before adapter migration.
  ComicEpisodeCatalogRepository? get comicEpisodeCatalog =>
      sourcePlan.comicEpisodeCatalog;
  ComicThreadDiscoveryRepository? get comicThreadDiscovery =>
      sourcePlan.comicThreadDiscovery;
  ThreadReplyPageRepository? get threadReplyPage => sourcePlan.threadReplyPage;

  Future<
    DataReadResult<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>
  >
  loadComicEpisodeCatalog(ComicEpisodeCatalogRequest request) =>
      sourcePlan.comicEpisodeCatalog?.loadCatalog(request) ??
      unsupported<ComicEpisodeImageCatalog, ComicEpisodeCatalogCapabilities>();

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

  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadThreadReplies({required String tid, required int page}) =>
      sourcePlan.threadReplyPage?.loadPage(tid: tid, page: page) ??
      unsupported<ThreadReplyPage, ThreadReplyPageReadCapabilities>();
}
