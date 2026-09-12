import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/domain/message_repository.dart';

class MessageTestRepository implements MessageRepository {
  final reads = <MessageTestRead>[];
  final sends = <MessageTestSend>[];
  final notificationReads = <MessageTestNotificationRead>[];
  final ignores = <MessageTestIgnore>[];

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
  Future<NotificationRead> loadNotifications(ForumNotificationQuery query) {
    final read = MessageTestNotificationRead(query);
    notificationReads.add(read);
    return read.result.future;
  }

  @override
  Future<DataCommandResult<ForumNotificationIgnoreReceipt>> ignore(
    ForumNotificationIgnoreSubmission submission,
  ) {
    final command = MessageTestIgnore(submission);
    ignores.add(command);
    return command.result.future;
  }
}

class MessageTestNotificationRead {
  MessageTestNotificationRead(this.query);
  final ForumNotificationQuery query;
  final result = Completer<NotificationRead>();
}

class MessageTestIgnore {
  MessageTestIgnore(this.submission);
  final ForumNotificationIgnoreSubmission submission;
  final result = Completer<DataCommandResult<ForumNotificationIgnoreReceipt>>();

  void succeed() => result.complete(
    DataCommandApplied(
      ForumNotificationIgnoreReceipt(
        notificationId: submission.notificationId,
        type: submission.type,
        authorId: submission.scope == ForumNotificationIgnoreScope.allAuthors
            ? '0'
            : submission.authorId,
      ),
    ),
  );
}

NotificationRead notificationTestPage(
  List<ForumNotificationItem> items, {
  int page = 1,
  int? count,
  int perPage = 20,
}) => DataReadSuccess(
  data: ForumNotificationPage(
    items: items,
    count: count ?? items.length,
    page: page,
    perPage: perPage,
  ),
  capabilities: ForumNotificationReadCapabilities(
    values: DataCapabilitySet.supported(ForumNotificationCapability.values),
  ),
  metadata: const DataReadMetadata.network(),
);

ForumNotificationItem notificationTestItem(
  String id, {
  String authorId = '20',
  String? markup,
}) => ForumNotificationItem(
  id: id,
  type: 'post',
  isNew: true,
  authorId: authorId,
  authorName: authorId == '0' ? '' : 'Alice',
  noteMarkup:
      markup ??
      '<p><a href="forum.php?mod=viewthread&amp;tid=42">Reply $id</a></p>',
  occurredAt: null,
  rawDateline: '2026-09-12',
);

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
  String recipient = '20',
}) => ForumPrivateMessageItem(
  messageId: id,
  conversationId: '91',
  isNew: false,
  subject: '',
  fromUserId: sender,
  fromUserName: sender == '10' ? 'Me' : 'Alice',
  toUserId: sender == '10' ? recipient : '10',
  toUserName: sender == '10' ? 'Alice' : 'Me',
  message: html ?? '<p>Message $id</p>',
  sentAt: DateTime(2026, 9, 12, 10, 30),
  rawDateline: '',
);
