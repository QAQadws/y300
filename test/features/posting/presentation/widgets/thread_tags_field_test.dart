import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/presentation/widgets/thread_tags_field.dart';

void main() {
  Widget wrap(Widget child) {
    return LocalizedTestApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(8), child: child)),
    );
  }

  testWidgets('renders existing tags as chips', (tester) async {
    await tester.pumpWidget(wrap(
      ThreadTagsField(
        tags: const ['百合', '动画'],
        onChanged: (_) {},
        chipKeyBuilder: (tag, index) => Key('chip-$index'),
      ),
    ));

    expect(find.byKey(const Key('chip-0')), findsOneWidget);
    expect(find.byKey(const Key('chip-1')), findsOneWidget);
    expect(find.text('百合'), findsOneWidget);
    expect(find.text('动画'), findsOneWidget);
  });

  testWidgets('comma in input triggers commit and clears the box',
      (tester) async {
    final captured = <List<String>>[];
    await tester.pumpWidget(wrap(
      ThreadTagsField(
        tags: const <String>[],
        onChanged: captured.add,
        inputFieldKey: const Key('input'),
      ),
    ));

    await tester.enterText(find.byKey(const Key('input')), '百合,');
    expect(captured.last, ['百合']);
  });

  testWidgets('enter submission also triggers commit', (tester) async {
    final captured = <List<String>>[];
    await tester.pumpWidget(wrap(
      ThreadTagsField(
        tags: const <String>[],
        onChanged: captured.add,
        inputFieldKey: const Key('input'),
      ),
    ));
    await tester.enterText(find.byKey(const Key('input')), '动画');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(captured.last, ['动画']);
  });

  testWidgets('hides input field once max reached', (tester) async {
    await tester.pumpWidget(wrap(
      ThreadTagsField(
        tags: const ['a', 'b'],
        onChanged: (_) {},
        maxTags: 2,
        inputFieldKey: const Key('input'),
      ),
    ));
    expect(find.byKey(const Key('input')), findsNothing);
  });
}
