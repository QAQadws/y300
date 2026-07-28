import 'package:y300/features/history/domain/models/history_models.dart';

typedef HistoryLocalTimeConverter = DateTime Function(DateTime value);

class HistoryDateGroup {
  const HistoryDateGroup({
    required this.localDate,
    required this.daysAgo,
    required this.entries,
  });

  final DateTime localDate;
  final int daysAgo;
  final List<HistoryEntry> entries;
}

class HistoryDateGroupingPolicy {
  const HistoryDateGroupingPolicy();

  List<HistoryDateGroup> group(
    List<HistoryEntry> entries, {
    required DateTime now,
    HistoryLocalTimeConverter toLocal = _defaultToLocal,
  }) {
    if (entries.isEmpty) {
      return const <HistoryDateGroup>[];
    }
    final localNow = toLocal(now);
    final todayOrdinal = _calendarOrdinal(localNow);
    final grouped = <DateTime, List<HistoryEntry>>{};
    for (final entry in entries) {
      final localVisit = toLocal(entry.lastVisitedAt);
      final day = DateTime(localVisit.year, localVisit.month, localVisit.day);
      grouped.putIfAbsent(day, () => <HistoryEntry>[]).add(entry);
    }

    final days = grouped.keys.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    return List<HistoryDateGroup>.unmodifiable(
      days.map((day) {
        final dayEntries = grouped[day]!
          ..sort((a, b) {
            final byTime = b.lastVisitedAt.compareTo(a.lastVisitedAt);
            if (byTime != 0) {
              return byTime;
            }
            final byType = a.target.type.name.compareTo(b.target.type.name);
            return byType != 0 ? byType : a.target.id.compareTo(b.target.id);
          });
        final daysAgo = todayOrdinal - _calendarOrdinal(day);
        return HistoryDateGroup(
          localDate: day,
          daysAgo: daysAgo,
          entries: List<HistoryEntry>.unmodifiable(dayEntries),
        );
      }),
    );
  }

  int _calendarOrdinal(DateTime value) {
    return DateTime.utc(
          value.year,
          value.month,
          value.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  static DateTime _defaultToLocal(DateTime value) => value.toLocal();
}
