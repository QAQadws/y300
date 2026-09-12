import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Verified article changes for the current account, without content or tickets.
final class BlogMutationBus extends ChangeNotifier {
  BlogMutationBus(this.accountId);
  final String? accountId;
  UserBlogReceipt? _last;
  bool _disposed = false;
  UserBlogReceipt? get last => _last;

  void publish(UserBlogReceipt receipt) {
    if (_disposed ||
        accountId == null ||
        receipt.target.actorUserId != accountId) {
      return;
    }
    _last = receipt;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _last = null;
    super.dispose();
  }
}
