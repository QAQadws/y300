import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/novel_pagination_profile.dart';

void main() {
  testWidgets('coverage reads only the mounted reader page-view prefix', (
    tester,
  ) async {
    Widget host(int? pageCount) => MaterialApp(
      home: Column(
        key: const Key('profile-root'),
        children: [
          Expanded(
            child: PageView.builder(
              key: const Key('unrelated-page-view'),
              itemCount: 99,
              itemBuilder: (_, _) => const SizedBox.shrink(),
            ),
          ),
          if (pageCount != null)
            Expanded(
              child: PageView.builder(
                key: const Key('novel-reader-paged-page-view'),
                itemCount: pageCount,
                itemBuilder: (_, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );

    int? observedCount() => visiblePaginationPageCount(
      tester.element(find.byKey(const Key('profile-root'))),
    );

    await tester.pumpWidget(host(2));
    expect(observedCount(), 2);
    await tester.pumpWidget(host(5));
    expect(observedCount(), 5);
    await tester.pumpWidget(host(null));
    expect(observedCount(), isNull);
  });

  test('a completed first readable frame is not a background interaction', () {
    expect(
      partialNavigationInvalidReason(
        firstReadableWasPartial: false,
        completed: true,
        requests: const [
          (
            pending: false,
            uncovered: true,
            accepted: true,
            covered: true,
            reached: true,
          ),
        ],
      ),
      'completed_before_first_input',
    );
  });

  test('turning covered pages does not prove an uncovered pending request', () {
    expect(
      partialNavigationInvalidReason(
        firstReadableWasPartial: true,
        completed: true,
        requests: const [
          (
            pending: true,
            uncovered: false,
            accepted: true,
            covered: true,
            reached: true,
          ),
          (
            pending: false,
            uncovered: true,
            accepted: true,
            covered: true,
            reached: true,
          ),
        ],
      ),
      'no_pending_uncovered_request',
    );
  });

  test(
    'pending acceptance requires target arrival and complete pagination',
    () {
      String? reason({
        required bool reached,
        required bool completed,
        bool covered = true,
      }) => partialNavigationInvalidReason(
        firstReadableWasPartial: true,
        completed: completed,
        requests: [
          (
            pending: true,
            uncovered: true,
            accepted: true,
            covered: covered,
            reached: reached,
          ),
        ],
      );

      expect(
        reason(reached: false, completed: true),
        'navigation_target_not_reached',
      );
      expect(
        reason(reached: true, completed: false),
        'pagination_not_completed',
      );
      expect(
        reason(reached: true, completed: true, covered: false),
        'navigation_target_not_reached',
      );
      expect(reason(reached: true, completed: true), isNull);
    },
  );

  test('navigation metadata is a separate short logcat record', () {
    for (final reason in [null, 'completed_before_first_input']) {
      final summary = navigationProfileSummary(
        name: 'complex-partial-navigation',
        invalidReason: reason,
        firstReadableWasPartial: reason == null,
        requestsWhilePending: 3,
        uncoveredRequestsWhilePending: 1,
        interactionWindowUs: 30000000,
      );
      expect(summary['event'], 'scenario_navigation_summary');
      expect(summary['valid'], reason == null);
      expect(summary['invalidReason'], reason);
      expect(summary['uncoveredRequestsWhilePending'], 1);
      expect(summary['coverageSource'], 'mounted-page-view');
      expect(summary['coveragePollMs'], 20);
      // Include the actual emitted prefix and UTF-8 bytes, leaving ample room
      // under Android's line cap for its own logger metadata.
      final line = 'NOVEL_PROFILE ${jsonEncode(summary)}';
      expect(utf8.encode(line).length, lessThan(2048));
    }
  });
}
