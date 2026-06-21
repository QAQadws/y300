import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';

class MyNotificationParser {
  const MyNotificationParser();

  MyNotificationPage parse(JsonMap variables) {
    final items = ParseUtils.asList(variables['list'])
        .map(ParseUtils.asMap)
        .where((item) => item.isNotEmpty)
        .map(_parseItem)
        .toList(growable: false);
    return MyNotificationPage(
      items: List<MyNotificationItem>.unmodifiable(items),
      count: ParseUtils.asInt(variables['count'], fallback: items.length),
      page: ParseUtils.asInt(variables['page'], fallback: 1),
      perPage: ParseUtils.asInt(variables['perpage']),
    );
  }

  MyNotificationItem _parseItem(JsonMap item) {
    return MyNotificationItem(
      id: ParseUtils.asString(item['id']),
      type: ParseUtils.asString(item['type']),
      isNew: ParseUtils.asBool(item['new']),
      authorId: ParseUtils.asString(item['authorid']),
      author: ParseUtils.asString(item['author']),
      noteHtml: ParseUtils.asString(item['note']),
      dateline: _formatUnixSeconds(ParseUtils.asString(item['dateline'])),
    );
  }
}

class MyPrivateMessageParser {
  const MyPrivateMessageParser();

  MyPrivateMessagePage parse(JsonMap variables) {
    final items = ParseUtils.asList(variables['list'])
        .map(ParseUtils.asMap)
        .where((item) => item.isNotEmpty)
        .map(_parseItem)
        .toList(growable: false);
    return MyPrivateMessagePage(
      items: List<MyPrivateMessageItem>.unmodifiable(items),
      count: ParseUtils.asInt(variables['count'], fallback: items.length),
      page: ParseUtils.asInt(variables['page'], fallback: 1),
      perPage: ParseUtils.asInt(variables['perpage']),
    );
  }

  MyPrivateMessageItem _parseItem(JsonMap item) {
    return MyPrivateMessageItem(
      plid: ParseUtils.asString(item['plid']),
      pmid: ParseUtils.asString(item['pmid']),
      isNew: ParseUtils.asBool(item['isnew']),
      subject: ParseUtils.asString(item['subject']),
      fromUid: ParseUtils.asString(item['msgfromid']),
      fromName: ParseUtils.asString(item['msgfrom']),
      toUid: ParseUtils.asString(item['touid']),
      toName: ParseUtils.asString(item['tousername']),
      message: ParseUtils.asString(item['message']),
      dateline: ParseUtils.asString(item['vdateline']),
    );
  }
}

String _formatUnixSeconds(String raw) {
  final seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds <= 0) {
    return raw;
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}-${twoDigits(dateTime.month)}-'
      '${twoDigits(dateTime.day)} ${twoDigits(dateTime.hour)}:'
      '${twoDigits(dateTime.minute)}';
}
