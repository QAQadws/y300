import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/domain/private_message_recipient_selection.dart';

void main() {
  test(
    'friend UID and exact username both deduplicate without losing order',
    () {
      final selection = PrivateMessageRecipientSelection();
      expect(
        selection.addFriend(userId: '20', username: 'Alice'),
        AddPrivateMessageRecipientResult.added,
      );
      expect(
        selection.addFriend(userId: '20', username: 'Renamed Alice'),
        AddPrivateMessageRecipientResult.duplicate,
      );
      expect(
        selection.addUsername(' Alice '),
        AddPrivateMessageRecipientResult.duplicate,
      );
      expect(
        selection.addUsername('Bob'),
        AddPrivateMessageRecipientResult.added,
      );
      expect(selection.usernameSnapshot(), ['Alice', 'Bob']);
      expect(selection.containsFriend('20', 'Renamed Alice'), isTrue);
      expect(selection.remove(selection.items.first), isTrue);
      expect(selection.usernameSnapshot(), ['Bob']);
    },
  );

  test('invalid names and IDs never enter a batch', () {
    final selection = PrivateMessageRecipientSelection();
    for (final name in [
      '',
      '  ',
      'Alice,Bob',
      'Alice\nBob',
      '\nAlice',
      'Alice\t',
      'Alice\u007f',
      'Alice\u0085Bob',
      'Alice\u009f',
      'x' * 257,
    ]) {
      expect(
        selection.addUsername(name),
        AddPrivateMessageRecipientResult.invalid,
      );
    }
    expect(
      selection.addFriend(userId: '0', username: 'Alice'),
      AddPrivateMessageRecipientResult.invalid,
    );
    expect(
      selection.addFriend(userId: '20', username: '\tAlice'),
      AddPrivateMessageRecipientResult.invalid,
    );
    expect(selection.isEmpty, isTrue);
  });

  test('selection stops at 20 and each send snapshot is immutable', () {
    final selection = PrivateMessageRecipientSelection();
    for (var i = 1; i <= PrivateMessageRecipientSelection.maxRecipients; i++) {
      expect(
        selection.addFriend(userId: '$i', username: 'user$i'),
        AddPrivateMessageRecipientResult.added,
      );
    }
    final snapshot = selection.usernameSnapshot();
    expect(
      selection.addUsername('extra'),
      AddPrivateMessageRecipientResult.full,
    );
    expect(snapshot, hasLength(20));
    expect(() => snapshot.add('extra'), throwsUnsupportedError);
    selection.remove(selection.items.first);
    expect(snapshot, hasLength(20));
    expect(
      selection.addUsername('extra'),
      AddPrivateMessageRecipientResult.added,
    );
  });
}
