import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef PrivateMessageRead =
    DataReadResult<
      ForumPrivateMessagePage,
      ForumPrivateMessageReadCapabilities
    >;
typedef NotificationRead =
    DataReadResult<ForumNotificationPage, ForumNotificationReadCapabilities>;

/// App boundary for mailbox reads and explicit writes, without protocol fields.
abstract interface class MessageRepository {
  Future<PrivateMessageRead> loadMessages(ForumPrivateMessageQuery query);
  Future<NotificationRead> loadNotifications(ForumNotificationQuery query);
  Future<DataCommandResult<ForumPrivateMessageReceipt>> send(
    ForumPrivateMessageSubmission submission,
  );
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> ignore(
    ForumNotificationIgnoreSubmission submission,
  );
}
