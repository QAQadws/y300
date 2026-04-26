import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/startup/presentation/startup_page.dart';

void main() {
  testWidgets('StartupPage should show skeleton and call onCompleted', (
    tester,
  ) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupPage(
          onCompleted: () {
            completed = true;
          },
        ),
      ),
    );

    expect(find.text('Y300'), findsOneWidget);
    expect(find.byKey(const Key('startup-forum-skeleton')), findsOneWidget);
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 901));
    expect(completed, isTrue);
  });
}
