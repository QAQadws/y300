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

    expect(groups.map((group) => group.daysAgo), <int>[0, 1, 6, 9]);
    expect(groups.last.localDate, DateTime(2026, 7, 8));
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

  test('keeps seven-day and cross-year groups as calendar dates', () {
    final groups = policy.group(
      <HistoryEntry>[
        historyEntry(
          type: HistoryTargetType.thread,
          id: 'year-end',
          title: 'year-end',
          visitedAt: DateTime.utc(2026, 1, 1, 1),
        ),
        historyEntry(
          type: HistoryTargetType.comic,
          id: 'seven-days',
          title: 'seven-days',
          visitedAt: DateTime.utc(2025, 12, 25, 1),
        ),
      ],
      now: DateTime.utc(2026, 1, 1, 12),
      toLocal: (value) => value.toUtc(),
    );

    expect(groups.map((group) => group.daysAgo), <int>[0, 7]);
    expect(groups.last.localDate, DateTime(2025, 12, 25));
  });
}
