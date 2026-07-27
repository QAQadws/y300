import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/thread_special_switch.dart';

void main() {
  Widget wrap(Widget child) => LocalizedTestApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('switch reflects current special and reports changes', (
    tester,
  ) async {
    NewThreadSpecial? captured;
    await tester.pumpWidget(
      wrap(
        ThreadSpecialSwitch(
          widgetKey: const Key('special'),
          pollItemKey: const Key('special-poll'),
          special: NewThreadSpecial.normal,
          onChanged: (next) => captured = next,
        ),
      ),
    );

    // 默认只显示当前类型，选项通过浮层菜单展示。
    expect(find.text('普通帖'), findsOneWidget);
    expect(find.text('投票'), findsNothing);

    await tester.tap(find.byKey(const Key('special')));
    await tester.pumpAndSettle();
    expect(find.text('投票'), findsOneWidget);

    await tester.tap(find.byKey(const Key('special-poll')));
    await tester.pumpAndSettle();
    expect(captured, NewThreadSpecial.poll);
  });

  testWidgets('disabled switch does not fire callback', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      wrap(
        ThreadSpecialSwitch(
          widgetKey: const Key('special'),
          pollItemKey: const Key('special-poll'),
          special: NewThreadSpecial.normal,
          enabled: false,
          onChanged: (_) => fired = true,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('special')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('special-poll')), findsNothing);
    expect(fired, isFalse);
  });
}
