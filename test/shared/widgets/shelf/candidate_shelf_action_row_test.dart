import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/shelf/candidate_shelf_action_row.dart';

void main() {
  testWidgets('CandidateShelfActionRow displays label and reacts to tap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: CandidateShelfActionRow(
            label: '测试候选',
            inShelf: false,
            isLoading: false,
            onPressed: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('测试候选'), findsOneWidget);
    expect(find.byKey(const Key('comic-add-to-shelf-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('comic-add-to-shelf-button')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
