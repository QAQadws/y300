/// Source-neutral preparation and mutation contracts for journal comments.
library;

import '../network/forum_request.dart' show ForumRequestCancellation;
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// A comment operation advertised by the current server page.
enum UserBlogCommentAction {
  /// Add a top-level comment.
  add,

  /// Reply to an existing comment.
  reply,

  /// Edit a comment permitted by the server.
  edit,

  /// Delete a comment permitted by the server.
  delete,
}

/// Stable identity and actor for one comment operation.
final class UserBlogCommentTarget {
  /// Creates an operation target. Existing-comment operations require a cid.
  const UserBlogCommentTarget({
    required this.actorUserId,
    required this.ownerUserId,
    required this.blogId,
    required this.action,
    this.commentId,
  });

  /// Signed-in user who is preparing this operation.
  final String actorUserId;

  /// Journal author's identity.
  final String ownerUserId;

  /// Journal identity.
  final String blogId;

  /// Requested operation.
  final UserBlogCommentAction action;

  /// Existing comment identity for reply, edit, and delete.
  final String? commentId;

  @override
  bool operator ==(Object other) =>
      other is UserBlogCommentTarget &&
      actorUserId == other.actorUserId &&
      ownerUserId == other.ownerUserId &&
      blogId == other.blogId &&
      action == other.action &&
      commentId == other.commentId;

  @override
  int get hashCode =>
      Object.hash(actorUserId, ownerUserId, blogId, action, commentId);
}

/// Opaque, transient proof of a prepared comment form. Never persist it.
abstract interface class UserBlogCommentPreparationToken {}

/// Server-provided editor values and a single-use submission proof.
final class UserBlogCommentPreparation {
  /// Creates a prepared form without exposing protocol fields to the Host.
  const UserBlogCommentPreparation({
    required this.target,
    required this.token,
    this.initialMessage = '',
  });

  /// Proven target and actor.
  final UserBlogCommentTarget target;

  /// Editable source text; empty for add/reply/delete.
  final String initialMessage;

  /// Adapter-owned form proof.
  final UserBlogCommentPreparationToken token;
}

/// User input submitted against a prepared form.
final class UserBlogCommentSubmission {
  /// Creates a submission. Delete ignores no text: its message must be empty.
  const UserBlogCommentSubmission({
    required this.preparation,
    required this.actorUserId,
    this.message = '',
    this.cancellation,
  });

  /// Current actor, checked again against the prepared actor and session.
  final String actorUserId;

  /// Prepared operation.
  final UserBlogCommentPreparation preparation;

  /// Comment source text, retained by the caller until applied.
  final String message;

  /// Caller-owned cancellation, including account and page disposal.
  final ForumRequestCancellation? cancellation;
}

/// Server-confirmed identity of a comment mutation.
final class UserBlogCommentReceipt {
  /// Creates a receipt. Addition/reply may be pending moderation on the server.
  const UserBlogCommentReceipt({required this.target, required this.commentId});

  /// Original operation and journal identity.
  final UserBlogCommentTarget target;

  /// Newly created or changed/deleted comment identity.
  final String commentId;
}

/// Current server form and structured comment commands on the shared transport.
abstract interface class UserBlogCommentService {
  /// Reads current permission and prepares an account-bound form.
  Future<
    DataReadResult<
      UserBlogCommentPreparation,
      DataCapabilitySet<UserBlogCommentAction>
    >
  >
  prepare(
    UserBlogCommentTarget target, {
    ForumRequestCancellation? cancellation,
  });

  /// Submits once; uncertain outcomes must never be automatically retried.
  Future<DataCommandResult<UserBlogCommentReceipt>> execute(
    UserBlogCommentSubmission submission,
  );
}
