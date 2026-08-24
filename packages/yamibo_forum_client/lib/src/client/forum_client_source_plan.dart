import '../contracts/comic_contracts.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/forum_directory.dart';
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

final class ForumClientSourcePlan {
  const ForumClientSourcePlan({
    this.forumDirectory,
    this.forumHome,
    this.forumDisplay,
    this.forumTagDirectory,
    this.favoriteForumDirectory,
    this.favoriteThreadDirectory,
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
  });
  final ForumDirectoryRepository? forumDirectory;
  final ForumHomeRepository? forumHome;
  final ForumDisplayRepository? forumDisplay;
  final ForumTagDirectoryRepository? forumTagDirectory;
  final FavoriteForumDirectoryRepository? favoriteForumDirectory;
  final FavoriteThreadDirectoryRepository? favoriteThreadDirectory;
  final CurrentUserProfileRepository? currentUserProfile;
  final ForumNotificationRepository? notifications;
  final ForumPrivateMessageRepository? privateMessages;
  final ForumStickerCatalogRepository? stickerCatalog;
  final ForumUserProfileRepository? forumUserProfile;
  final UserBlogDirectoryRepository? userBlogDirectory;
  final UserBlogDetailRepository? userBlogDetail;
  final ForumSearchRepository? forumSearch;
  final ComicEpisodeCatalogRepository? comicEpisodeCatalog;
  final ComicThreadDiscoveryRepository? comicThreadDiscovery;
  final ThreadReplyPageRepository? threadReplyPage;
  final ThreadRepository? threadDetail;
  final ThreadRepository? threadIngestionDetail;
  final ThreadPostRatingsRepository? postRatings;
  final ThreadPostLocatorRepository? postLocator;
  final ThreadAuthorPostRepository? threadAuthorPosts;
}
