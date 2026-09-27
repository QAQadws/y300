import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/presentation/conversation_message_presentation.dart';

void main() {
  final start = DateTime(2026, 9, 12, 10, 30);

  test('groups adjacent authors below five minutes, including equal times', () {
    final rows = deriveConversationMessagePresentations([
      _item('1', time: start),
      _item('2', time: start),
      _item('3', time: start.add(const Duration(minutes: 4, seconds: 59))),
      _item('4', time: start.add(const Duration(minutes: 9, seconds: 59))),
      _item('5', time: start.add(const Duration(minutes: 10)), sender: '30'),
    ]);

    expect(rows.map((row) => row.isGroupStart), [
      true,
      false,
      false,
      true,
      true,
    ]);
    expect(rows.map((row) => row.showTimestamp), [
      true,
      false,
      false,
      true,
      false,
    ]);
    expect(rows.map((row) => row.isFirst), [true, false, false, false, false]);
  });

  test('local day changes and backward timestamps never group', () {
    final rows = deriveConversationMessagePresentations([
      _item('1', time: DateTime(2026, 9, 12, 23, 59)),
      _item('2', time: DateTime(2026, 9, 13, 0, 1)),
      _item('3', time: DateTime(2026, 9, 13, 0, 0)),
    ]);

    expect(rows.map((row) => row.isGroupStart), [true, true, true]);
    expect(rows.map((row) => row.showTimestamp), [true, true, false]);
  });

  test('unknown times break groups and preserve only available raw labels', () {
    final rows = deriveConversationMessagePresentations([
      _item('1', time: start),
      _item('2', rawDateline: 'server date'),
      _item('3'),
      _item('4', time: start),
      _item('5', time: start, sender: ''),
      _item('6', time: start, sender: ''),
    ]);

    expect(rows.map((row) => row.isGroupStart), everyElement(isTrue));
    expect(rows.map((row) => row.showTimestamp), [
      true,
      true,
      false,
      true,
      false,
      false,
    ]);
  });

  test('appending messages cannot alter any existing row boundary', () {
    final items = [_item('1', time: start), _item('2', time: start)];
    final before = deriveConversationMessagePresentations(items);
    final after = deriveConversationMessagePresentations([
      ...items,
      _item('3', time: start, sender: '30'),
    ]);

    for (var index = 0; index < before.length; index++) {
      expect(after[index].item, same(items[index]));
      expect(after[index].isFirst, before[index].isFirst);
      expect(after[index].isGroupStart, before[index].isGroupStart);
      expect(after[index].showTimestamp, before[index].showTimestamp);
    }
    expect(items.map((item) => item.messageId), ['1', '2']);
    expect(() => after.clear(), throwsUnsupportedError);
  });

  test(
    'direct titles use peer identity in either direction, never local name',
    () {
      const target = ForumConversationTarget.direct('20');
      expect(resolveConversationTitle([_item('1')], target, ''), 'Alice');
      expect(
        resolveConversationTitle(
          [
            _item('1'),
            _item(
              '2',
              sender: '10',
              senderName: 'Me',
              recipientName: 'Alice updated',
            ),
          ],
          target,
          '',
        ),
        'Alice updated',
      );
      expect(
        resolveConversationTitle(
          [
            _item(
              '1',
              sender: '30',
              senderName: 'Other',
              recipient: '10',
              recipientName: 'Me',
            ),
          ],
          target,
          '',
        ),
        isNull,
      );
      expect(
        resolveConversationTitle([], target, '  Chosen title  '),
        'Chosen title',
      );
    },
  );

  test(
    'group titles use the most recent nonempty subject or return fallback',
    () {
      const target = ForumConversationTarget.group('91');
      expect(
        resolveConversationTitle(
          [
            _item('1', subject: 'Old group'),
            _item('2', subject: 'New group'),
            _item('3'),
          ],
          target,
          '',
        ),
        'New group',
      );
      expect(resolveConversationTitle([_item('1')], target, ' '), isNull);
    },
  );
}

ForumPrivateMessageItem _item(
  String id, {
  DateTime? time,
  String rawDateline = '',
  String sender = '20',
  String senderName = 'Alice',
  String recipient = '20',
  String recipientName = 'Alice',
  String subject = '',
}) => ForumPrivateMessageItem(
  messageId: id,
  conversationId: '91',
  isNew: false,
  subject: subject,
  fromUserId: sender,
  fromUserName: senderName,
  toUserId: recipient,
  toUserName: recipientName,
  message: '<p>$id</p>',
  sentAt: time,
  rawDateline: rawDateline,
);
