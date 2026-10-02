import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/messages/domain/private_message_compose_repository.dart';

final privateMessageComposeRepositoryProvider =
    Provider<PrivateMessageComposeRepository>(
      (ref) => ClientPrivateMessageComposeRepository(
        ref.watch(yamiboForumClientProvider),
      ),
    );

final class ClientPrivateMessageComposeRepository
    implements PrivateMessageComposeRepository {
  const ClientPrivateMessageComposeRepository(this._client);

  final YamiboForumClient _client;

  @override
  Future<FriendDirectoryRead> loadFriends(ForumFriendDirectoryQuery query) =>
      _client.loadFriends(query);

  @override
  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> sendBatch(
    ForumPrivateMessageBatchSubmission submission,
  ) => _client.sendPrivateMessageBatch(submission);
}
