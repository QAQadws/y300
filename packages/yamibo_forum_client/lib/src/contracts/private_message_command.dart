/// Sending private messages through a source-neutral, explicit write contract.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';

/// How the server identifies the destination of one message.
enum ForumPrivateMessageRecipientKind {
  /// One recipient identified by user ID.
  user,

  /// One recipient identified by their exact username.
  username,

  /// An existing group, addressed through a message from that conversation.
  group,
}

/// A single destination; sending to multiple arbitrary users is not implicit.
final class ForumPrivateMessageRecipient {
  /// Sends to one user ID.
  const ForumPrivateMessageRecipient.user(this.value)
    : kind = ForumPrivateMessageRecipientKind.user,
      replyMessageId = null;

  /// Sends to one exact username, without display-script conversion.
  const ForumPrivateMessageRecipient.username(this.value)
    : kind = ForumPrivateMessageRecipientKind.username,
      replyMessageId = null;

  /// Replies using the group ID and message anchor returned by a prior read.
  const ForumPrivateMessageRecipient.group({
    required String conversationId,
    required String this.replyMessageId,
  }) : value = conversationId,
       kind = ForumPrivateMessageRecipientKind.group;

  /// Determines whether [value] is a user ID, username or group ID.
  final ForumPrivateMessageRecipientKind kind;

  /// Destination identity in the namespace selected by [kind].
  final String value;

  /// Required only for a reply to an existing group conversation.
  final String? replyMessageId;
}

/// User-approved content to send once. Callers retain it on uncertain outcomes.
final class ForumPrivateMessageSubmission {
  /// Creates a message submission; no network action occurs on construction.
  const ForumPrivateMessageSubmission({
    required this.recipient,
    required this.message,
    this.cancellation,
  });

  /// Explicit recipient, independent of display names and rendered links.
  final ForumPrivateMessageRecipient recipient;

  /// Original user input, passed without HTML or script conversion.
  final String message;

  /// Cancellation does not imply rollback after the write starts.
  final ForumRequestCancellation? cancellation;
}

/// Confirmed server receipt; a plain successful HTTP response is insufficient.
final class ForumPrivateMessageReceipt {
  /// Records the server-issued message ID and the submitted destination.
  const ForumPrivateMessageReceipt({
    required this.messageId,
    required this.recipient,
  });

  /// Newly issued server message ID.
  final String messageId;

  /// Destination of the confirmed message.
  final ForumPrivateMessageRecipient recipient;
}

/// Sends one message, never automatically retrying an inconclusive write.
abstract interface class ForumPrivateMessageCommand {
  /// Returns applied only after receiving explicit server success evidence.
  Future<DataCommandResult<ForumPrivateMessageReceipt>> execute(
    ForumPrivateMessageSubmission submission,
  );
}
