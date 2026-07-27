import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/presentation/widgets/thread_subject_field.dart';

void main() {
  Widget wrap(Widget child) => LocalizedTestApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('uses underline-only decoration', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(ThreadSubjectField(controller: controller, onChanged: (_) {})),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;

    expect(decoration.filled, isFalse);
    expect(decoration.border, isA<UnderlineInputBorder>());
    expect(decoration.enabledBorder, isA<UnderlineInputBorder>());
    expect(decoration.focusedBorder, isA<UnderlineInputBorder>());
    expect(decoration.border, isNot(isA<OutlineInputBorder>()));
  });
}
