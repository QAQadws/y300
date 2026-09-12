import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/messages/domain/message_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => ClientMessageRepository(ref.watch(yamiboForumClientProvider)),
);

final class ClientMessageRepository implements MessageRepository {
  const ClientMessageRepository(this._client);
  final YamiboForumClient _client;

  @override
  Future<PrivateMessageRead> loadMessages(ForumPrivateMessageQuery query) =>
      _client.loadPrivateMessages(query);
  @override
  Future<NotificationRead> loadNotifications(ForumNotificationQuery query) =>
      _client.loadNotifications(query);
  @override
  Future<DataCommandResult<ForumPrivateMessageReceipt>> send(
    ForumPrivateMessageSubmission submission,
  ) => _client.sendPrivateMessage(submission);
  @override
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> ignore(
    ForumNotificationIgnoreSubmission submission,
  ) => _client.ignoreNotifications(submission);
}
