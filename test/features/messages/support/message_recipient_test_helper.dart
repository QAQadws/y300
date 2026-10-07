import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/presentation/widgets/message_friend_picker_sheet.dart';

Future<void> addMessageRecipient(WidgetTester tester, String username) async {
  await tester.tap(find.byKey(const Key('message-friends-open')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('message-recipient')), username);
  final add = find.byKey(const Key('message-recipient-add'));
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  await dismissMessageRecipientPicker(tester);
}

Future<void> dismissMessageRecipientPicker(WidgetTester tester) async {
  final sheet = tester.getRect(find.byType(MessageFriendPickerSheet));
  expect(sheet.top, greaterThan(0));
  await tester.tapAt(Offset(sheet.center.dx, sheet.top / 2));
  await tester.pumpAndSettle();
  expect(find.byType(MessageFriendPickerSheet), findsNothing);
}
