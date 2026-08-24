/// Read contracts for notifications and private-message directories.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

final class ForumNotificationQuery {
  const ForumNotificationQuery();
}

final class ForumNotificationItem {
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
  final String id;
  final String type;
  final bool isNew;
  final String authorId;
  final String authorName;
  final String noteMarkup;
  final DateTime? occurredAt;
  final String rawDateline;
}

final class ForumNotificationPage {
  const ForumNotificationPage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
  });
  final List<ForumNotificationItem> items;
  final int count;
  final int page;
  final int perPage;
}

enum ForumNotificationCapability {
  stableIdentity,
  orderedItems,
  unreadState,
  actorIdentity,
  bodyMarkup,
  occurrenceTime,
  paginationSummary,
}

final class ForumNotificationSourceCapabilities {
  const ForumNotificationSourceCapabilities({required this.values});
  final DataCapabilitySet<ForumNotificationCapability> values;
  ForumNotificationReadCapabilities toReadCapabilities() =>
      ForumNotificationReadCapabilities(values: values);
}

final class ForumNotificationReadCapabilities {
  const ForumNotificationReadCapabilities({required this.values});
  final DataCapabilitySet<ForumNotificationCapability> values;
}

abstract interface class ForumNotificationRepository {
  ForumNotificationSourceCapabilities get capabilities;
  Future<
    DataReadResult<ForumNotificationPage, ForumNotificationReadCapabilities>
  >
  load(
    ForumNotificationQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

final class ForumPrivateMessageQuery {
  const ForumPrivateMessageQuery();
}

final class ForumPrivateMessageItem {
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
  final String messageId;
  final String? conversationId;
  final bool isNew;
  final String subject;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final String message;
  final DateTime? sentAt;
  final String rawDateline;
}

final class ForumPrivateMessagePage {
  const ForumPrivateMessagePage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
  });
  final List<ForumPrivateMessageItem> items;
  final int count;
  final int page;
  final int perPage;
}

enum ForumPrivateMessageCapability {
  stableIdentity,
  conversationIdentity,
  orderedItems,
  unreadState,
  participantIdentity,
  messagePreview,
  occurrenceTime,
  paginationSummary,
}

final class ForumPrivateMessageSourceCapabilities {
  const ForumPrivateMessageSourceCapabilities({required this.values});
  final DataCapabilitySet<ForumPrivateMessageCapability> values;
  ForumPrivateMessageReadCapabilities toReadCapabilities() =>
      ForumPrivateMessageReadCapabilities(values: values);
}

final class ForumPrivateMessageReadCapabilities {
  const ForumPrivateMessageReadCapabilities({required this.values});
  final DataCapabilitySet<ForumPrivateMessageCapability> values;
}

abstract interface class ForumPrivateMessageRepository {
  ForumPrivateMessageSourceCapabilities get capabilities;
  Future<
    DataReadResult<ForumPrivateMessagePage, ForumPrivateMessageReadCapabilities>
  >
  load(
    ForumPrivateMessageQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
