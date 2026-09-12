/// Journal editing and management, separate from comment operations.
library;

import '../network/forum_request.dart' show ForumRequestCancellation;
import 'data_command_contract.dart';
import 'data_read_contract.dart';
import 'profile_and_blog.dart';

/// Transient operation identity, including the expected signed-in actor.
final class UserBlogTarget {
  /// Creates a target; creation has no blog ID and uses the actor as author.
  const UserBlogTarget({
    required this.actorUserId,
    required this.ownerUserId,
    required this.action,
    this.blogId,
  });

  /// Signed-in actor.
  final String actorUserId;

  /// Journal author.
  final String ownerUserId;

  /// Operation.
  final UserBlogAction action;

  /// Existing journal identity, absent for creation.
  final String? blogId;
  @override
  bool operator ==(Object other) =>
      other is UserBlogTarget &&
      actorUserId == other.actorUserId &&
      ownerUserId == other.ownerUserId &&
      action == other.action &&
      blogId == other.blogId;
  @override
  int get hashCode => Object.hash(actorUserId, ownerUserId, action, blogId);
}

/// Non-secret description of the access policy retained while editing.
enum UserBlogVisibility {
  /// Visible to everyone.
  public,

  /// Visible to friends.
  friends,

  /// Visible to specified friends.
  selectedFriends,

  /// Visible only to the author.
  private,

  /// Protected by the existing password.
  passwordProtected,
}

/// Opaque form ticket. Includes protected fields and must never be persisted.
abstract interface class UserBlogOperationToken {}

/// Editable values and choices advertised by the current complete form.
final class UserBlogEditorPreparation {
  /// Creates a prepared editor.
  const UserBlogEditorPreparation({
    required this.target,
    required this.token,
    required this.subject,
    required this.bodyHtml,
    required this.tags,
    required this.siteCategories,
    required this.personalCategories,
    required this.siteCategoryId,
    required this.personalCategoryId,
    required this.siteCategoryRequired,
    required this.canCreateCategory,
    required this.canPublishFeed,
    required this.publishFeed,
    required this.visibility,
    required this.commentsEnabled,
  });

  /// Proven operation target.
  final UserBlogTarget target;

  /// Transient adapter proof.
  final UserBlogOperationToken token;

  /// Existing title.
  final String subject;

  /// Original editable HTML, preserved without lossy plain-text conversion.
  final String bodyHtml;

  /// Server tag source.
  final String tags;

  /// Available site categories.
  final List<UserBlogCategory> siteCategories;

  /// Available personal categories.
  final List<UserBlogCategory> personalCategories;

  /// Existing site category, or zero for no category.
  final String siteCategoryId;

  /// Existing personal category, or zero for no category.
  final String personalCategoryId;

  /// Whether the site requires a nonzero category.
  final bool siteCategoryRequired;

  /// Whether creating a personal category is advertised.
  final bool canCreateCategory;

  /// Whether a publish-to-feed option exists.
  final bool canPublishFeed;

  /// Initial publish-to-feed preference.
  final bool publishFeed;

  /// Existing access policy; editing does not change it implicitly.
  final UserBlogVisibility visibility;

  /// Whether the preserved policy allows comments.
  final bool commentsEnabled;
}

/// Edited content. Access fields are deliberately kept in the opaque ticket.
final class UserBlogEditorSubmission {
  /// Creates a submission against one prepared form.
  const UserBlogEditorSubmission({
    required this.preparation,
    required this.actorUserId,
    required this.subject,
    required this.bodyHtml,
    required this.tags,
    required this.siteCategoryId,
    required this.personalCategoryId,
    required this.publishFeed,
    this.newPersonalCategory,
    this.cancellation,
  });

  /// Prepared form.
  final UserBlogEditorPreparation preparation;

  /// Current signed-in actor.
  final String actorUserId;

  /// User-edited title.
  final String subject;

  /// User-edited HTML.
  final String bodyHtml;

  /// Tag text.
  final String tags;

  /// Selected site category.
  final String siteCategoryId;

  /// Selected personal category.
  final String personalCategoryId;

  /// Optional new personal category, mutually exclusive with a nonzero ID.
  final String? newPersonalCategory;

  /// Whether to publish a feed entry when supported.
  final bool publishFeed;

  /// Caller-owned cancellation.
  final ForumRequestCancellation? cancellation;
}

/// A server-prepared delete, pin, or unpin confirmation.
final class UserBlogActionPreparation {
  /// Creates a confirmation ticket.
  const UserBlogActionPreparation({required this.target, required this.token});

  /// Proven operation target.
  final UserBlogTarget target;

  /// Single-use form proof.
  final UserBlogOperationToken token;
}

/// Confirmed journal mutation identity; public display may await moderation.
final class UserBlogReceipt {
  /// Creates a receipt without server message payloads.
  const UserBlogReceipt({required this.target, required this.blogId});

  /// Original target, including actor and action.
  final UserBlogTarget target;

  /// Created, edited, or removed journal ID.
  final String blogId;
}

/// Journal publishing, editing, and management on the shared session.
abstract interface class UserBlogOperations {
  /// Reads the complete editor and preserves access settings.
  Future<
    DataReadResult<UserBlogEditorPreparation, DataCapabilitySet<UserBlogAction>>
  >
  prepareEditor(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  });

  /// Saves a prepared editor once; uncertain effects must not be retried.
  Future<DataCommandResult<UserBlogReceipt>> save(
    UserBlogEditorSubmission submission,
  );

  /// Prepares an operation before presenting its user confirmation.
  Future<
    DataReadResult<UserBlogActionPreparation, DataCapabilitySet<UserBlogAction>>
  >
  prepareAction(
    UserBlogTarget target, {
    ForumRequestCancellation? cancellation,
  });

  /// Executes a user-confirmed management operation once.
  Future<DataCommandResult<UserBlogReceipt>> executeAction(
    UserBlogActionPreparation preparation, {
    required String actorUserId,
    ForumRequestCancellation? cancellation,
  });
}
