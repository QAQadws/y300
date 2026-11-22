import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_chapter_interactions_button.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('rapid dock visibility changes keep one action mounted', (
    tester,
  ) async {
    late StateSetter update;
    var visible = true;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return NovelReaderChapterInteractionsButton(
                visible: visible,
                busy: false,
                onPressed: () {},
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(
      const Key('novel-reader-chapter-interactions-button'),
    );
    final original = tester.element(action);

    for (final next in [false, true, false, true]) {
      update(() => visible = next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(action.hitTestable(), next ? findsOneWidget : findsNothing);
      expect(tester.getSize(action), const Size.square(48));
    }
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.element(action), same(original));
  });
}
