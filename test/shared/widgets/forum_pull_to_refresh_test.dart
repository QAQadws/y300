import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/forum_pull_to_refresh.dart';

void main() {
  group('ForumPullToRefresh', () {
    testWidgets('triggers onRefresh by dragging a list shorter than the '
        'viewport', (tester) async {
      var refreshCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForumPullToRefresh(
              onRefresh: () async {
                refreshCount++;
              },
              child: ListView(
                key: const Key('short-list'),
                physics: ForumPullToRefresh.scrollPhysics,
                children: const [SizedBox(height: 40, child: Text('唯一一行'))],
              ),
            ),
          ),
        ),
      );

      await tester.fling(
        find.byKey(const Key('short-list')),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(refreshCount, 1);
    });

    testWidgets('uses the scheme primary color for the indicator', (
      tester,
    ) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A4A2B)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ForumPullToRefresh(
              onRefresh: () async {},
              child: ListView(
                physics: ForumPullToRefresh.scrollPhysics,
                children: const [SizedBox(height: 40)],
              ),
            ),
          ),
        ),
      );

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      expect(indicator.color, theme.colorScheme.primary);
    });
  });
}
