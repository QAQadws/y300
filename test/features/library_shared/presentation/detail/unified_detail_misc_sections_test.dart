import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_misc_sections.dart';

void main() {
  testWidgets('long intro fades at three lines and expands from whole area', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => UnifiedDetailIntroSection(
                  intro: List<String>.generate(
                    8,
                    (index) => '这是简介的第 ${index + 1} 行内容',
                  ).join('\n'),
                  expanded: expanded,
                  onToggle: () => setState(() => expanded = !expanded),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    Text introText() =>
        tester.widget<Text>(find.byKey(const Key('unified-detail-intro-text')));
    AnimatedRotation arrow() => tester.widget<AnimatedRotation>(
      find.byKey(const Key('unified-detail-intro-arrow')),
    );

    expect(introText().maxLines, 3);
    expect(find.byKey(const Key('unified-detail-intro-fade')), findsOneWidget);
    expect(arrow().turns, 0);
    final collapsedHeight = tester
        .getSize(find.byKey(const Key('unified-detail-intro-section')))
        .height;

    await tester.tap(find.byKey(const Key('unified-detail-intro-toggle')));
    await tester.pumpAndSettle();

    expect(expanded, isTrue);
    expect(introText().maxLines, isNull);
    expect(find.byKey(const Key('unified-detail-intro-fade')), findsNothing);
    expect(arrow().turns, 0.5);
    expect(
      tester
          .getSize(find.byKey(const Key('unified-detail-intro-section')))
          .height,
      greaterThan(collapsedHeight),
    );
  });

  testWidgets('short intro has no fade or redundant expand arrow', (
    tester,
  ) async {
    var toggleCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: UnifiedDetailIntroSection(
                intro: '短简介',
                expanded: false,
                onToggle: () => toggleCount += 1,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-intro-fade')), findsNothing);
    expect(find.byKey(const Key('unified-detail-intro-arrow')), findsNothing);
    await tester.tap(find.byKey(const Key('unified-detail-intro-toggle')));
    await tester.pump();
    expect(toggleCount, 0);
  });
}
