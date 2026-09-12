import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// The actor and article identity of a personal blog bookmark.
final class UserBlogFavoriteTarget {
  /// Creates an account-bound favorite target.
  const UserBlogFavoriteTarget({
    required this.actorUserId,
    required this.ownerUserId,
    required this.blogId,
  });

  /// Signed-in reader creating the bookmark.
  final String actorUserId;

  /// Article author, required by the source's bookmark operation.
  final String ownerUserId;

  /// Article identity.
  final String blogId;

  @override
  bool operator ==(Object other) =>
      other is UserBlogFavoriteTarget &&
      other.actorUserId == actorUserId &&
      other.ownerUserId == ownerUserId &&
      other.blogId == blogId;

  @override
  int get hashCode => Object.hash(actorUserId, ownerUserId, blogId);
}

/// Opaque one-use proof of a prepared bookmark form. Never persist this value.
abstract interface class UserBlogFavoriteToken {}

/// Either a writable form or a proven existing bookmark, without server HTML.
final class UserBlogFavoritePreparation {
  /// A form that requires an explicit add command.
  const UserBlogFavoritePreparation.ready({
    required this.target,
    required UserBlogFavoriteToken this.token,
  }) : existingFavoriteId = null;

  /// An existing bookmark; no mutation is necessary or authorized by this value.
  const UserBlogFavoritePreparation.alreadySaved({
    required this.target,
    required String favoriteId,
  }) : existingFavoriteId = favoriteId,
       token = null;

  /// Account and article verified during preparation.
  final UserBlogFavoriteTarget target;

  /// Source-owned form ticket, present only for a new bookmark.
  final UserBlogFavoriteToken? token;

  /// Existing remote bookmark identity, proven by an account-bound read.
  final String? existingFavoriteId;
}

/// Verified personal bookmark identity returned by the source.
final class UserBlogFavoriteReceipt {
  /// Creates a receipt after validating the actor, article, and bookmark ID.
  const UserBlogFavoriteReceipt({
    required this.target,
    required this.favoriteId,
  });

  /// Original account and article.
  final UserBlogFavoriteTarget target;

  /// Positive source bookmark identity.
  final String favoriteId;
}

/// Native mobile bookmark preparation and a single explicit submission.
abstract interface class UserBlogFavoriteService {
  /// Verifies the article and current account, then reads the bookmark form.
  Future<DataReadResult<UserBlogFavoritePreparation, Object?>> prepare(
    UserBlogFavoriteTarget target, {
    ForumRequestCancellation? cancellation,
  });

  /// Adds the bookmark once. An unknown result must never be automatically retried.
  Future<DataCommandResult<UserBlogFavoriteReceipt>> add(
    UserBlogFavoritePreparation preparation, {
    required String actorUserId,
    required String description,
    ForumRequestCancellation? cancellation,
  });
}
