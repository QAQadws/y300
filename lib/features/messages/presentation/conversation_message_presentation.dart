import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Presentation boundaries derived before the timeline splits its two slivers.
class ConversationMessagePresentation {
  const ConversationMessagePresentation({
    required this.item,
    required this.isGroupStart,
    required this.showTimestamp,
    this.isFirst = false,
  });

  final ForumPrivateMessageItem item;
  final bool isGroupStart;
  final bool showTimestamp;
  final bool isFirst;
}

List<ConversationMessagePresentation> deriveConversationMessagePresentations(
  List<ForumPrivateMessageItem> items,
) {
  final presentations = <ConversationMessagePresentation>[];
  ForumPrivateMessageItem? previous;
  for (final item in items) {
    final time = item.sentAt?.toLocal();
    final previousTime = previous?.sentAt?.toLocal();
    final sameDay =
        time != null &&
        previousTime != null &&
        time.year == previousTime.year &&
        time.month == previousTime.month &&
        time.day == previousTime.day;
    final gap = time != null && previousTime != null
        ? time.difference(previousTime)
        : null;
    final closeInTime =
        sameDay &&
        gap != null &&
        !gap.isNegative &&
        gap < const Duration(minutes: 5);
    presentations.add(
      ConversationMessagePresentation(
        item: item,
        isFirst: previous == null,
        isGroupStart:
            !closeInTime ||
            item.fromUserId.isEmpty ||
            item.fromUserId != previous?.fromUserId,
        showTimestamp: time == null
            ? item.rawDateline.trim().isNotEmpty
            : previousTime == null ||
                  !sameDay ||
                  gap! >= const Duration(minutes: 5),
      ),
    );
    previous = item;
  }
  return List.unmodifiable(presentations);
}

/// Uses only a name that belongs to the requested peer, never the local author.
String? resolveConversationTitle(
  List<ForumPrivateMessageItem> items,
  ForumConversationTarget target,
  String providedTitle,
) {
  final explicit = providedTitle.trim();
  if (explicit.isNotEmpty) return explicit;
  for (final item in items.reversed) {
    if (target.kind == ForumConversationKind.group) {
      final title = item.subject.trim();
      if (title.isNotEmpty) return title;
    } else {
      final name = item.fromUserId == target.id
          ? item.fromUserName.trim()
          : item.toUserId == target.id
          ? item.toUserName.trim()
          : '';
      if (name.isNotEmpty) return name;
    }
  }
  return null;
}
