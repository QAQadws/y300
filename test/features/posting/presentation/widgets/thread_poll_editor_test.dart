import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/presentation/widgets/thread_poll_editor.dart';

void main() {
  Widget wrap(Widget child) =>
      LocalizedTestApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('renders existing options and reports add/remove', (tester) async {
    var lastOptions = const <String>['A', 'B'];
    await tester.pumpWidget(wrap(StatefulBuilder(
      builder: (context, setState) {
        return ThreadPollEditor(
          containerKey: const Key('poll'),
          optionFieldKeyBuilder: (i) => Key('opt-$i'),
          optionRemoveKeyBuilder: (i) => Key('rm-$i'),
          addOptionButtonKey: const Key('add'),
          poll: NewThreadPollDraft(options: lastOptions),
          onOptionsChanged: (next) => setState(() => lastOptions = next),
          onMultipleChanged: (_) {},
          onMaxChoicesChanged: (_) {},
          onExpirationDaysChanged: (_) {},
          onOvertChanged: (_) {},
          onVisibilityPollChanged: (_) {},
        );
      },
    )));

    expect(find.byKey(const Key('opt-0')), findsOneWidget);
    expect(find.byKey(const Key('opt-1')), findsOneWidget);

    // 添加。
    await tester.tap(find.byKey(const Key('add')));
    await tester.pumpAndSettle();
    expect(lastOptions.length, 3);

    // 删除第一个。
    await tester.tap(find.byKey(const Key('rm-0')));
    await tester.pumpAndSettle();
    expect(lastOptions.length, 2);
    expect(lastOptions.first, 'B');
  });

  testWidgets('shows max-choices field only when multiple is on', (tester) async {
    await tester.pumpWidget(wrap(ThreadPollEditor(
      maxChoicesFieldKey: const Key('mc'),
      poll: const NewThreadPollDraft(options: ['A', 'B', 'C']),
      onOptionsChanged: (_) {},
      onMultipleChanged: (_) {},
      onMaxChoicesChanged: (_) {},
      onExpirationDaysChanged: (_) {},
      onOvertChanged: (_) {},
      onVisibilityPollChanged: (_) {},
    )));
    expect(find.byKey(const Key('mc')), findsNothing);

    await tester.pumpWidget(wrap(ThreadPollEditor(
      maxChoicesFieldKey: const Key('mc'),
      poll: const NewThreadPollDraft(
        options: ['A', 'B', 'C'],
        multiple: true,
        maxChoices: 2,
      ),
      onOptionsChanged: (_) {},
      onMultipleChanged: (_) {},
      onMaxChoicesChanged: (_) {},
      onExpirationDaysChanged: (_) {},
      onOvertChanged: (_) {},
      onVisibilityPollChanged: (_) {},
    )));
    expect(find.byKey(const Key('mc')), findsOneWidget);
  });
}
