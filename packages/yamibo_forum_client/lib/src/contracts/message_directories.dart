/// Read contracts for notifications and private-message directories.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import '../network/forum_request.dart';

/// Query parameters for forum notification.
final class ForumNotificationQuery {
  /// Creates a [ForumNotificationQuery].
  const ForumNotificationQuery({this.page = 1, this.cancellation});

  /// One-based page; reading can mark notifications as read on the server.
  final int page;

  /// Cancels an obsolete page or account read.
  final ForumRequestCancellation? cancellation;
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
    this.duplicateCount = 0,
    this.authorAvatarUrl,
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

  /// Validated author avatar reference, when the source can resolve it.
  final String? authorAvatarUrl;

  /// Note markup.
  final String noteMarkup;

  /// Additional matching notifications suppressed by the source for this row.
  final int duplicateCount;

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
  /// Reads the conversation directory in most-recent-first order.
  const ForumPrivateMessageQuery({this.page = 1, this.cancellation})
    : target = null;

  /// Reads messages in chronological order within a conversation page.
  ///
  /// Zero selects the latest page. Older history has smaller page numbers.
  const ForumPrivateMessageQuery.conversation({
    required ForumConversationTarget this.target,
    this.page = 0,
    this.cancellation,
  });

  /// Null for the directory, otherwise the conversation to read.
  final ForumConversationTarget? target;

  /// One-based page, or zero for the latest conversation page.
  final int page;

  /// Cancels an obsolete page or account read.
  final ForumRequestCancellation? cancellation;
}

/// A direct recipient and a group conversation use different server identities.
enum ForumConversationKind {
  /// A conversation with one other user.
  direct,

  /// An existing multi-user conversation.
  group,
}

/// Identifies a conversation without exposing a transport URL.
final class ForumConversationTarget {
  /// Opens a direct conversation by recipient user ID.
  const ForumConversationTarget.direct(this.id)
    : kind = ForumConversationKind.direct;

  /// Opens an existing group conversation by conversation ID.
  const ForumConversationTarget.group(this.id)
    : kind = ForumConversationKind.group;

  /// Recipient user ID or group conversation ID, according to [kind].
  final String id;

  /// Determines which identity namespace [id] belongs to.
  final ForumConversationKind kind;

  @override
  bool operator ==(Object other) =>
      other is ForumConversationTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
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
    this.isGroupConversation = false,
    this.participantCount = 0,
    this.fromUserAvatarUrl,
    this.toUserAvatarUrl,
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

  /// Validated sender avatar reference, independent of the conversation peer.
  final String? fromUserAvatarUrl;

  /// To user id.
  final String toUserId;

  /// To user name.
  final String toUserName;

  /// Validated avatar for [toUserId], when supplied by the source.
  final String? toUserAvatarUrl;

  /// Message.
  final String message;

  /// Sent at.
  final DateTime? sentAt;

  /// Raw dateline.
  final String rawDateline;

  /// Whether this directory entry represents a multi-user conversation.
  final bool isGroupConversation;

  /// Number of participants when supplied by the directory.
  final int participantCount;

  /// The directory's routable target, or null if the source omitted it.
  ForumConversationTarget? get target {
    if (!isGroupConversation && toUserId.isNotEmpty && toUserId != '0') {
      return ForumConversationTarget.direct(toUserId);
    }
    final id = conversationId;
    return id == null || id.isEmpty || id == '0'
        ? null
        : ForumConversationTarget.group(id);
  }
}

/// Source-neutral forum private message page.
final class ForumPrivateMessagePage {
  /// Creates a [ForumPrivateMessagePage].
  const ForumPrivateMessagePage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
    this.currentUserId = '',
    this.replyMessageId = '',
  });

  /// Items.
  final List<ForumPrivateMessageItem> items;

  /// Count.
  final int count;

  /// Requested or current one-based page.
  final int page;

  /// Per page.
  final int perPage;

  /// Account associated with this response; used to distinguish outgoing rows.
  final String currentUserId;

  /// Server-provided message anchor needed when replying to a group.
  final String replyMessageId;

  /// Whether a later page exists (newer messages for a conversation).
  bool get hasNext => perPage > 0 && page * perPage < count;

  /// Whether an earlier page exists (older messages for a conversation).
  bool get hasPrevious => page > 1;
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
