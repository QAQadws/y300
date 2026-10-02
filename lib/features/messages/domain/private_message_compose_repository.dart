import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef FriendDirectoryRead =
    DataReadResult<
      ForumFriendDirectoryPage,
      ForumFriendDirectoryReadCapabilities
    >;

/// Compose-only forum operations. The app never builds a second PM transport.
abstract interface class PrivateMessageComposeRepository {
  Future<FriendDirectoryRead> loadFriends(ForumFriendDirectoryQuery query);

  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> sendBatch(
    ForumPrivateMessageBatchSubmission submission,
  );
}
