import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/profile/data/services/my_message_parser.dart';

void main() {
  test('MyNotificationParser parses my notifications sample', () {
    final json =
        jsonDecode(File('docs/html/我的资料/我的提醒.json').readAsStringSync())
            as Map<String, dynamic>;
    const parser = MyNotificationParser();

    final page = parser.parse(ParseUtils.asMap(json['Variables']));

    expect(page.count, 7);
    expect(page.page, 1);
    expect(page.items, hasLength(7));
    expect(page.items.first.id, '4117644');
    expect(page.items.first.type, 'pcomment');
    expect(page.items.first.author, '筱林透');
    expect(page.items.first.noteHtml, contains('点评了您'));
    expect(page.items.first.dateline, isNotEmpty);
  });

  test('MyPrivateMessageParser parses my private messages sample', () {
    final json =
        jsonDecode(File('docs/html/我的资料/我的消息.json').readAsStringSync())
            as Map<String, dynamic>;
    const parser = MyPrivateMessageParser();

    final page = parser.parse(ParseUtils.asMap(json['Variables']));

    expect(page.count, 1);
    expect(page.page, 1);
    expect(page.items, hasLength(1));
    expect(page.items.first.pmid, '133466');
    expect(page.items.first.fromName, '2834758851');
    expect(page.items.first.toName, '筱林透');
    expect(page.items.first.message, '好的，我QQ就是2834758851');
  });
}
