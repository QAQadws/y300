import '../contracts/comic_contracts.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_search.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/thread_reply_page.dart';

final class ForumClientSourcePlan {
  const ForumClientSourcePlan({
    this.forumDirectory,
    this.forumTagDirectory,
    this.favoriteForumDirectory,
    this.favoriteThreadDirectory,
    this.currentUserProfile,
    this.forumUserProfile,
    this.userBlogDirectory,
    this.userBlogDetail,
    this.forumSearch,
    this.comicEpisodeCatalog,
    this.comicThreadDiscovery,
    this.threadReplyPage,
  });
  final ForumDirectoryRepository? forumDirectory;
  final ForumTagDirectoryRepository? forumTagDirectory;
  final FavoriteForumDirectoryRepository? favoriteForumDirectory;
  final FavoriteThreadDirectoryRepository? favoriteThreadDirectory;
  final CurrentUserProfileRepository? currentUserProfile;
  final ForumUserProfileRepository? forumUserProfile;
  final UserBlogDirectoryRepository? userBlogDirectory;
  final UserBlogDetailRepository? userBlogDetail;
  final ForumSearchRepository? forumSearch;
  final ComicEpisodeCatalogRepository? comicEpisodeCatalog;
  final ComicThreadDiscoveryRepository? comicThreadDiscovery;
  final ThreadReplyPageRepository? threadReplyPage;
}
