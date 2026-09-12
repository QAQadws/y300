import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Lightweight invalidation data; origin is an opaque marker, never a page or
/// controller. Retaining the last event must not retain a closed reading tree.
final class BlogMutation {
  const BlogMutation({
    required this.ownerUserId,
    required this.blogId,
    this.articleAction,
    this.commentAction,
    this.origin,
  });
  final String ownerUserId;
  final String blogId;
  final UserBlogAction? articleAction;
  final UserBlogCommentAction? commentAction;
  final Object? origin;
}

/// Verified article changes for the current account, without content or tickets.
final class BlogMutationBus extends ChangeNotifier {
  BlogMutationBus(this.accountId);
  final String? accountId;
  BlogMutation? _last;
  bool _disposed = false;
  BlogMutation? get last => _last;

  void publish(UserBlogReceipt receipt) {
    if (_disposed ||
        accountId == null ||
        receipt.target.actorUserId != accountId) {
      return;
    }
    _last = BlogMutation(
      ownerUserId: receipt.target.ownerUserId,
      blogId: receipt.blogId,
      articleAction: receipt.target.action,
    );
    notifyListeners();
  }

  void publishComment(UserBlogCommentReceipt receipt, {Object? origin}) {
    if (_disposed ||
        accountId == null ||
        receipt.target.actorUserId != accountId) {
      return;
    }
    _last = BlogMutation(
      ownerUserId: receipt.target.ownerUserId,
      blogId: receipt.target.blogId,
      commentAction: receipt.target.action,
      origin: origin,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _last = null;
    super.dispose();
  }
}
