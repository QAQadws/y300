/// Read contracts for notifications and private-message directories.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Query parameters for forum notification.
final class ForumNotificationQuery {
  /// Creates a [ForumNotificationQuery].
  const ForumNotificationQuery();
}

/// Source-neutral forum notification item.
final class ForumNotificationItem {
  /// Creates a [ForumNotificationItem].
  const ForumNotificationItem({
    required this.id,
    required this.type,
    required this.isNew,
    required this.authorId,
    required this.authorName,
    required this.noteMarkup,
    required this.occurredAt,
    required this.rawDateline,
  });

  /// Stable notification identifier.
  final String id;

  /// Type.
  final String type;

  /// Is new.
  final bool isNew;

  /// Stable author identifier.
  final String authorId;

  /// Author name.
  final String authorName;

  /// Note markup.
  final String noteMarkup;

  /// Occurred at.
  final DateTime? occurredAt;

  /// Raw dateline.
  final String rawDateline;
}

/// Source-neutral forum notification page.
final class ForumNotificationPage {
  /// Creates a [ForumNotificationPage].
  const ForumNotificationPage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
  });

  /// Items.
  final List<ForumNotificationItem> items;

  /// Count.
  final int count;

  /// Requested or current one-based page.
  final int page;

  /// Per page.
  final int perPage;
}

/// Capabilities exposed by forum notification.
enum ForumNotificationCapability {
  /// Stable identity.
  stableIdentity,

  /// Ordered items.
  orderedItems,

  /// Unread state.
  unreadState,

  /// Actor identity.
  actorIdentity,

  /// Body markup.
  bodyMarkup,

  /// Occurrence time.
  occurrenceTime,

  /// Pagination summary.
  paginationSummary,
}

/// Capabilities declared by the forum notification source.
final class ForumNotificationSourceCapabilities {
  /// Creates a [ForumNotificationSourceCapabilities].
  const ForumNotificationSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumNotificationCapability> values;

  /// Converts this value to read capabilities.
  ForumNotificationReadCapabilities toReadCapabilities() =>
      ForumNotificationReadCapabilities(values: values);
}

/// Capabilities effective for one forum notification read.
final class ForumNotificationReadCapabilities {
  /// Creates a [ForumNotificationReadCapabilities].
  const ForumNotificationReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumNotificationCapability> values;
}

/// Loads forum notification data through a source-neutral contract.
abstract interface class ForumNotificationRepository {
  /// Capabilities declared by this source.
  ForumNotificationSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ForumNotificationPage, ForumNotificationReadCapabilities>
  >
  load(
    ForumNotificationQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// Query parameters for forum private message.
final class ForumPrivateMessageQuery {
  /// Creates a [ForumPrivateMessageQuery].
  const ForumPrivateMessageQuery();
}

/// Source-neutral forum private message item.
final class ForumPrivateMessageItem {
  /// Creates a [ForumPrivateMessageItem].
  const ForumPrivateMessageItem({
    required this.messageId,
    required this.conversationId,
    required this.isNew,
    required this.subject,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.message,
    required this.sentAt,
    required this.rawDateline,
  });

  /// Message id.
  final String messageId;

  /// Conversation id.
  final String? conversationId;

  /// Is new.
  final bool isNew;

  /// Subject.
  final String subject;

  /// From user id.
  final String fromUserId;

  /// From user name.
  final String fromUserName;

  /// To user id.
  final String toUserId;

  /// To user name.
  final String toUserName;

  /// Message.
  final String message;

  /// Sent at.
  final DateTime? sentAt;

  /// Raw dateline.
  final String rawDateline;
}

/// Source-neutral forum private message page.
final class ForumPrivateMessagePage {
  /// Creates a [ForumPrivateMessagePage].
  const ForumPrivateMessagePage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
  });

  /// Items.
  final List<ForumPrivateMessageItem> items;

  /// Count.
  final int count;

  /// Requested or current one-based page.
  final int page;

  /// Per page.
  final int perPage;
}

/// Capabilities exposed by forum private message.
enum ForumPrivateMessageCapability {
  /// Stable identity.
  stableIdentity,

  /// Conversation identity.
  conversationIdentity,

  /// Ordered items.
  orderedItems,

  /// Unread state.
  unreadState,

  /// Participant identity.
  participantIdentity,

  /// Message preview.
  messagePreview,

  /// Occurrence time.
  occurrenceTime,

  /// Pagination summary.
  paginationSummary,
}

/// Capabilities declared by the forum private message source.
final class ForumPrivateMessageSourceCapabilities {
  /// Creates a [ForumPrivateMessageSourceCapabilities].
  const ForumPrivateMessageSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumPrivateMessageCapability> values;

  /// Converts this value to read capabilities.
  ForumPrivateMessageReadCapabilities toReadCapabilities() =>
      ForumPrivateMessageReadCapabilities(values: values);
}

/// Capabilities effective for one forum private message read.
final class ForumPrivateMessageReadCapabilities {
  /// Creates a [ForumPrivateMessageReadCapabilities].
  const ForumPrivateMessageReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ForumPrivateMessageCapability> values;
}

/// Loads forum private message data through a source-neutral contract.
abstract interface class ForumPrivateMessageRepository {
  /// Capabilities declared by this source.
  ForumPrivateMessageSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ForumPrivateMessagePage, ForumPrivateMessageReadCapabilities>
  >
  load(
    ForumPrivateMessageQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
