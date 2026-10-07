import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> addMessageRecipient(WidgetTester tester, String username) async {
  await tester.tap(find.byKey(const Key('message-friends-open')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('message-recipient')), username);
  final add = find.byKey(const Key('message-recipient-add'));
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('message-friends-done')));
  await tester.pumpAndSettle();
}
