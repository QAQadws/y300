import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/message_repository.dart';

class MessageTestRepository implements MessageRepository {
  final reads = <MessageTestRead>[];
  final sends = <MessageTestSend>[];

  @override
  Future<PrivateMessageRead> loadMessages(ForumPrivateMessageQuery query) {
    final read = MessageTestRead(query);
    reads.add(read);
    return read.result.future;
  }

  @override
  Future<DataCommandResult<ForumPrivateMessageReceipt>> send(
    ForumPrivateMessageSubmission submission,
  ) {
    final send = MessageTestSend(submission);
    sends.add(send);
    return send.result.future;
  }

  @override
  Future<NotificationRead> loadNotifications(ForumNotificationQuery query) =>
      throw StateError('Unexpected notification read');

  @override
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> ignore(
    ForumNotificationIgnoreSubmission submission,
  ) => throw StateError('Unexpected notification command');
}

class MessageTestRead {
  MessageTestRead(this.query);
  final ForumPrivateMessageQuery query;
  final result = Completer<PrivateMessageRead>();
}

class MessageTestSend {
  MessageTestSend(this.submission);
  final ForumPrivateMessageSubmission submission;
  final result = Completer<DataCommandResult<ForumPrivateMessageReceipt>>();

  void succeed({String id = '100'}) => result.complete(
    DataCommandApplied(
      ForumPrivateMessageReceipt(
        messageId: id,
        recipient: submission.recipient,
      ),
    ),
  );
}

PrivateMessageRead messageTestPage(
  List<ForumPrivateMessageItem> items, {
  int page = 1,
  int? count,
  int perPage = 20,
  String owner = '10',
  String anchor = '',
}) => DataReadSuccess(
  data: ForumPrivateMessagePage(
    items: items,
    count: count ?? items.length,
    page: page,
    perPage: perPage,
    currentUserId: owner,
    replyMessageId: anchor,
  ),
  capabilities: ForumPrivateMessageReadCapabilities(
    values: DataCapabilitySet.supported(ForumPrivateMessageCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);

ForumPrivateMessageItem messageTestItem(
  String id, {
  String? html,
  String sender = '20',
}) => ForumPrivateMessageItem(
  messageId: id,
  conversationId: '91',
  isNew: false,
  subject: '',
  fromUserId: sender,
  fromUserName: sender == '10' ? 'Me' : 'Alice',
  toUserId: sender == '10' ? '20' : '10',
  toUserName: sender == '10' ? 'Alice' : 'Me',
  message: html ?? '<p>Message $id</p>',
  sentAt: DateTime(2026, 9, 12, 10, 30),
  rawDateline: '',
);
