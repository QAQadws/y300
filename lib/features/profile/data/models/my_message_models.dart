class MyMessageCenterData {
  const MyMessageCenterData({
    required this.notifications,
    required this.privateMessages,
  });

  final MyNotificationPage notifications;
  final MyPrivateMessagePage privateMessages;
}

class MyNotificationPage {
  const MyNotificationPage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
  });

  final List<MyNotificationItem> items;
  final int count;
  final int page;
  final int perPage;
}

class MyNotificationItem {
  const MyNotificationItem({
    required this.id,
    required this.type,
    required this.isNew,
    required this.authorId,
    required this.author,
    required this.noteHtml,
    required this.dateline,
  });

  final String id;
  final String type;
  final bool isNew;
  final String authorId;
  final String author;
  final String noteHtml;
  final String dateline;
}

class MyPrivateMessagePage {
  const MyPrivateMessagePage({
    required this.items,
    required this.count,
    required this.page,
    required this.perPage,
  });

  final List<MyPrivateMessageItem> items;
  final int count;
  final int page;
  final int perPage;
}

class MyPrivateMessageItem {
  const MyPrivateMessageItem({
    required this.plid,
    required this.pmid,
    required this.isNew,
    required this.subject,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.toName,
    required this.message,
    required this.dateline,
  });

  final String plid;
  final String pmid;
  final bool isNew;
  final String subject;
  final String fromUid;
  final String fromName;
  final String toUid;
  final String toName;
  final String message;
  final String dateline;
}
