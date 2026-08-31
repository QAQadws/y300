import '../contracts/comic_contracts.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/favorite_commands.dart';
import '../contracts/forum_directory.dart';
import '../contracts/forum_authentication.dart';
import '../contracts/forum_home.dart';
import '../contracts/forum_image_attachments.dart';
import '../contracts/forum_display_repository.dart';
import '../contracts/forum_search.dart';
import '../contracts/forum_tag_directory.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/message_directories.dart';
import '../contracts/sticker_catalog.dart';
import '../contracts/thread_reply_page.dart';
import '../contracts/thread_repository.dart';
import '../contracts/thread_interaction_commands.dart';
import '../contracts/thread_poll_vote_command.dart';
import '../contracts/thread_composer_commands.dart';
import '../contracts/thread_post_edit.dart';
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
    this.postRatingPreparation,
    this.postRatingCommand,
    this.postCommentPreparation,
    this.postCommentCommand,
    this.threadPollVoteCommand,
    this.threadCreationPreparation,
    this.threadCreationCommand,
    this.threadReplyPreparation,
    this.threadReplyCommand,
    this.threadPostEditPreparation,
    this.threadPostEditCommand,
    this.imageAttachmentUploadPreparation,
    this.imageAttachmentUploadCommand,
    this.unusedImageAttachments,
    this.unusedImageAttachmentDelete,
    this.postImageAttachmentDelete,
    this.postRatings,
    this.postLocator,
    this.threadAuthorPosts,
    this.session,
    this.passwordLogin,
    this.logout,
  });

  /// Overlays non-null [overrides] on this source plan.
  ///
  /// This supports replacing one business source without introducing a global
  /// HTML/API mode. Null entries deliberately retain the existing source.
  ForumClientSourcePlan overlay(
    ForumClientSourcePlan overrides,
  ) => ForumClientSourcePlan(
    forumDirectory: overrides.forumDirectory ?? forumDirectory,
    forumHome: overrides.forumHome ?? forumHome,
    forumDisplay: overrides.forumDisplay ?? forumDisplay,
    forumTagDirectory: overrides.forumTagDirectory ?? forumTagDirectory,
    favoriteForumDirectory:
        overrides.favoriteForumDirectory ?? favoriteForumDirectory,
    favoriteThreadDirectory:
        overrides.favoriteThreadDirectory ?? favoriteThreadDirectory,
    favoriteForumCommand:
        overrides.favoriteForumCommand ?? favoriteForumCommand,
    favoriteThreadCommand:
        overrides.favoriteThreadCommand ?? favoriteThreadCommand,
    currentUserProfile: overrides.currentUserProfile ?? currentUserProfile,
    notifications: overrides.notifications ?? notifications,
    privateMessages: overrides.privateMessages ?? privateMessages,
    stickerCatalog: overrides.stickerCatalog ?? stickerCatalog,
    forumUserProfile: overrides.forumUserProfile ?? forumUserProfile,
    userBlogDirectory: overrides.userBlogDirectory ?? userBlogDirectory,
    userBlogDetail: overrides.userBlogDetail ?? userBlogDetail,
    forumSearch: overrides.forumSearch ?? forumSearch,
    comicEpisodeCatalog: overrides.comicEpisodeCatalog ?? comicEpisodeCatalog,
    comicThreadDiscovery:
        overrides.comicThreadDiscovery ?? comicThreadDiscovery,
    threadReplyPage: overrides.threadReplyPage ?? threadReplyPage,
    threadDetail: overrides.threadDetail ?? threadDetail,
    threadIngestionDetail:
        overrides.threadIngestionDetail ?? threadIngestionDetail,
    postRatingPreparation:
        overrides.postRatingPreparation ?? postRatingPreparation,
    postRatingCommand: overrides.postRatingCommand ?? postRatingCommand,
    postCommentPreparation:
        overrides.postCommentPreparation ?? postCommentPreparation,
    postCommentCommand: overrides.postCommentCommand ?? postCommentCommand,
    threadPollVoteCommand:
        overrides.threadPollVoteCommand ?? threadPollVoteCommand,
    threadCreationPreparation:
        overrides.threadCreationPreparation ?? threadCreationPreparation,
    threadCreationCommand:
        overrides.threadCreationCommand ?? threadCreationCommand,
    threadReplyPreparation:
        overrides.threadReplyPreparation ?? threadReplyPreparation,
    threadReplyCommand: overrides.threadReplyCommand ?? threadReplyCommand,
    threadPostEditPreparation:
        overrides.threadPostEditPreparation ?? threadPostEditPreparation,
    threadPostEditCommand:
        overrides.threadPostEditCommand ?? threadPostEditCommand,
    imageAttachmentUploadPreparation:
        overrides.imageAttachmentUploadPreparation ??
        imageAttachmentUploadPreparation,
    imageAttachmentUploadCommand:
        overrides.imageAttachmentUploadCommand ?? imageAttachmentUploadCommand,
    unusedImageAttachments:
        overrides.unusedImageAttachments ?? unusedImageAttachments,
    unusedImageAttachmentDelete:
        overrides.unusedImageAttachmentDelete ?? unusedImageAttachmentDelete,
    postImageAttachmentDelete:
        overrides.postImageAttachmentDelete ?? postImageAttachmentDelete,
    postRatings: overrides.postRatings ?? postRatings,
    postLocator: overrides.postLocator ?? postLocator,
    threadAuthorPosts: overrides.threadAuthorPosts ?? threadAuthorPosts,
    session: overrides.session ?? session,
    passwordLogin: overrides.passwordLogin ?? passwordLogin,
    logout: overrides.logout ?? logout,
  );

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

  /// Source for preparing a server-validated post-rating form.
  final ThreadPostRatingPreparationRepository? postRatingPreparation;

  /// Command for submitting a prepared post rating.
  final ThreadPostRatingCommand? postRatingCommand;

  /// Source for preparing a server-validated post-comment form.
  final ThreadPostCommentPreparationRepository? postCommentPreparation;

  /// Command for submitting a prepared post comment.
  final ThreadPostCommentCommand? postCommentCommand;

  /// Command for submitting a thread poll vote.
  final ThreadPollVoteCommand? threadPollVoteCommand;

  /// Source for preparing a server-validated thread-creation form.
  final ThreadCreationPreparationRepository? threadCreationPreparation;

  /// Command for creating a prepared thread.
  final ThreadCreationCommand? threadCreationCommand;

  /// Source for preparing a server-validated post reply.
  final ThreadReplyPreparationRepository? threadReplyPreparation;

  /// Command for submitting thread and post replies.
  final ThreadReplyCommand? threadReplyCommand;

  /// Source for preparing an ordinary post edit.
  final ThreadPostEditPreparationRepository? threadPostEditPreparation;

  /// Command for submitting a prepared ordinary post edit.
  final ThreadPostEditCommand? threadPostEditCommand;

  /// Source for current image attachment upload permission.
  final ForumImageAttachmentUploadPreparationRepository?
  imageAttachmentUploadPreparation;

  /// Command for streaming one image attachment upload.
  final ForumImageAttachmentUploadCommand? imageAttachmentUploadCommand;

  /// Source for the authenticated user's unused image attachments.
  final ForumUnusedImageAttachmentDirectoryRepository? unusedImageAttachments;

  /// Command for deleting an unused image attachment.
  final ForumUnusedImageAttachmentDeleteCommand? unusedImageAttachmentDelete;

  /// Command for deleting an existing post image attachment.
  final ForumPostImageAttachmentDeleteCommand? postImageAttachmentDelete;

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
