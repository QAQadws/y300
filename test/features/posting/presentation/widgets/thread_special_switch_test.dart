import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/thread_special_switch.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('switch reflects current special and reports changes',
      (tester) async {
    NewThreadSpecial? captured;
    await tester.pumpWidget(wrap(
      ThreadSpecialSwitch(
        widgetKey: const Key('special'),
        special: NewThreadSpecial.normal,
        onChanged: (next) => captured = next,
      ),
    ));

    // 显示两段。
    expect(find.text('普通帖'), findsOneWidget);
    expect(find.text('投票'), findsOneWidget);

    await tester.tap(find.text('投票'));
    await tester.pumpAndSettle();
    expect(captured, NewThreadSpecial.poll);
  });

  testWidgets('disabled switch does not fire callback', (tester) async {
    var fired = false;
    await tester.pumpWidget(wrap(
      ThreadSpecialSwitch(
        special: NewThreadSpecial.normal,
        enabled: false,
        onChanged: (_) => fired = true,
      ),
    ));
    await tester.tap(find.text('投票'));
    await tester.pumpAndSettle();
    expect(fired, isFalse);
  });
}
