import '../contracts/comic_contracts.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/favorite_commands.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_authentication.dart';
import '../contracts/forum_home.dart';
import '../contracts/forum_display_repository.dart';
import '../contracts/forum_search.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/message_directories.dart';
import '../contracts/sticker_catalog.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_repository.dart';
import '../contracts/thread_supplemental_reads.dart';

/// Experimental per-contract source composition used by advanced hosts.
///
/// Omitted contracts fail closed through the `YamiboForumClient` facade.
/// Standard clients should use `YamiboForumClientBuilder.buildStandardClient`
/// instead.
final class ForumClientSourcePlan {
  /// Creates a source plan from independently replaceable read contracts.
  const ForumClientSourcePlan({
    this.forumDirectory,
    this.forumHome,
    this.forumDisplay,
    this.forumTagDirectory,
    this.favoriteForumDirectory,
    this.favoriteThreadDirectory,
    this.favoriteForumCommand,
    this.favoriteThreadCommand,
    this.currentUserProfile,
    this.notifications,
    this.privateMessages,
    this.stickerCatalog,
    this.forumUserProfile,
    this.userBlogDirectory,
    this.userBlogDetail,
    this.forumSearch,
    this.comicEpisodeCatalog,
    this.comicThreadDiscovery,
    this.threadReplyPage,
    this.threadDetail,
    this.threadIngestionDetail,
    this.postRatings,
    this.postLocator,
    this.threadAuthorPosts,
    this.session,
    this.passwordLogin,
    this.logout,
  });

  /// Source for the forum hierarchy.
  final ForumDirectoryRepository? forumDirectory;

  /// Source for the combined forum-home document.
  final ForumHomeRepository? forumHome;

  /// Source for a forum's thread listing.
  final ForumDisplayRepository? forumDisplay;

  /// Source for forum Tag directories.
  final ForumTagDirectoryRepository? forumTagDirectory;

  /// Source for the authenticated user's favorite forums.
  final FavoriteForumDirectoryRepository? favoriteForumDirectory;

  /// Source for the authenticated user's favorite threads.
  final FavoriteThreadDirectoryRepository? favoriteThreadDirectory;

  /// Command for changing one forum's favorite state.
  final FavoriteForumCommand? favoriteForumCommand;

  /// Command for changing one thread's favorite state.
  final FavoriteThreadCommand? favoriteThreadCommand;

  /// Source for the authenticated user's profile projection.
  final CurrentUserProfileRepository? currentUserProfile;

  /// Source for notification pages.
  final ForumNotificationRepository? notifications;

  /// Source for private-message pages.
  final ForumPrivateMessageRepository? privateMessages;

  /// Source for the forum sticker catalog.
  final ForumStickerCatalogRepository? stickerCatalog;

  /// Source for public user profiles.
  final ForumUserProfileRepository? forumUserProfile;

  /// Source for a user's blog directory.
  final UserBlogDirectoryRepository? userBlogDirectory;

  /// Source for an individual blog entry.
  final UserBlogDetailRepository? userBlogDetail;

  /// Source for forum search.
  final ForumSearchRepository? forumSearch;

  /// Source for ordered comic episode image catalogs.
  final ComicEpisodeCatalogRepository? comicEpisodeCatalog;

  /// Source for comic thread discovery documents.
  final ComicThreadDiscoveryRepository? comicThreadDiscovery;

  /// Source for paged thread replies.
  final ThreadReplyPageRepository? threadReplyPage;

  /// Source used by ordinary thread-detail presentation.
  final ThreadRepository? threadDetail;

  /// Source used by workflows that ingest structured thread data.
  final ThreadRepository? threadIngestionDetail;

  /// Source for complete post-rating details.
  final ThreadPostRatingsRepository? postRatings;

  /// Source for locating a post within a paginated thread.
  final ThreadPostLocatorRepository? postLocator;

  /// Source for author-filtered post pages.
  final ThreadAuthorPostRepository? threadAuthorPosts;

  /// Source for authoritative Cookie-backed session resolution.
  final ForumSessionRepository? session;

  /// Source for password login.
  final ForumPasswordLoginCommand? passwordLogin;

  /// Source for standard logout.
  final ForumLogoutCommand? logout;
}
