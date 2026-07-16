import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_date_grouping_policy.dart';

import '../test_support/history_test_support.dart';

void main() {
  const policy = HistoryDateGroupingPolicy();

  test('groups by local calendar day across a UTC midnight boundary', () {
    DateTime toShanghai(DateTime value) {
      return value.toUtc().add(const Duration(hours: 8));
    }

    final groups = policy.group(
      <HistoryEntry>[
        historyEntry(
          type: HistoryTargetType.thread,
          id: 'today',
          title: '今天',
          visitedAt: DateTime.utc(2026, 7, 16, 16, 5),
        ),
        historyEntry(
          type: HistoryTargetType.comic,
          id: 'yesterday',
          title: '昨天',
          visitedAt: DateTime.utc(2026, 7, 16, 15, 59),
        ),
        historyEntry(
          type: HistoryTargetType.novel,
          id: 'six-days',
          title: '六天前',
          visitedAt: DateTime.utc(2026, 7, 11, 14),
        ),
        historyEntry(
          type: HistoryTargetType.thread,
          id: 'old',
          title: '更早',
          visitedAt: DateTime.utc(2026, 7, 8, 14),
        ),
      ],
      now: DateTime.utc(2026, 7, 16, 17),
      toLocal: toShanghai,
    );

    expect(groups.map((group) => group.label), <String>[
      '今天',
      '1 天前',
      '6 天前',
      '2026/7/8',
    ]);
    expect(groups.first.entries.single.target.id, 'today');
  });

  test('keeps deterministic order inside a same-time date group', () {
    final at = DateTime.utc(2026, 7, 16, 12);
    final groups = policy.group(
      <HistoryEntry>[
        historyEntry(
          type: HistoryTargetType.thread,
          id: '2',
          title: 'thread 2',
          visitedAt: at,
        ),
        historyEntry(
          type: HistoryTargetType.comic,
          id: '1',
          title: 'comic 1',
          visitedAt: at,
        ),
        historyEntry(
          type: HistoryTargetType.thread,
          id: '1',
          title: 'thread 1',
          visitedAt: at,
        ),
      ],
      now: at,
      toLocal: (value) => value.toUtc(),
    );

    expect(groups.single.entries.map((entry) => entry.target.toString()), [
      'comic:1',
      'thread:1',
      'thread:2',
    ]);
  });
}
