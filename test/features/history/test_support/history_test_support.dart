import 'dart:async';

import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_use_cases.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';
import 'package:y300/features/history/presentation/controllers/history_controller.dart';

class MemoryHistoryRepository implements HistoryRepository {
  MemoryHistoryRepository([Iterable<HistoryEntry> initial = const []]) {
    for (final entry in initial) {
      _entries[entry.target] = entry;
    }
  }

  final Map<HistoryTargetKey, HistoryEntry> _entries =
      <HistoryTargetKey, HistoryEntry>{};
  final StreamController<HistoryChange> _changes =
      StreamController<HistoryChange>.broadcast(sync: true);

  int queryCount = 0;
  bool failNextQuery = false;
  bool failCursorQuery = false;
  bool failDelete = false;
  bool failRestore = false;
  bool failClear = false;

  @override
  Future<void> recordVisit(HistoryEntry candidate) async {
    _entries[candidate.target] = candidate;
    _changes.add(
      HistoryChange(kind: HistoryChangeKind.recorded, target: candidate.target),
    );
  }

  @override
  Future<HistoryQueryPage> query(HistoryQuery query) async {
    queryCount += 1;
    if (failNextQuery || (failCursorQuery && query.cursor != null)) {
      failNextQuery = false;
      throw StateError('query failed');
    }
    final search = query.searchText.trim().toLowerCase();
    final items = _entries.values.where((entry) {
      if (query.targetTypes.isNotEmpty &&
          !query.targetTypes.contains(entry.target.type)) {
        return false;
      }
      if (search.isEmpty) {
        return true;
      }
      return <String>[
        entry.title,
        entry.contextLabel,
        entry.forumName ?? '',
        entry.target.id,
      ].any((value) => value.toLowerCase().contains(search));
    }).toList()..sort(compareHistoryEntries);
    final cursor = query.cursor;
    final afterCursor = cursor == null
        ? items
        : items.where((entry) => _isAfterCursor(entry, cursor)).toList();
    final visible = afterCursor.take(query.limit).toList(growable: false);
    final hasMore = afterCursor.length > visible.length;
    return HistoryQueryPage(
      items: visible,
      hasMore: hasMore,
      nextCursor: hasMore && visible.isNotEmpty ? visible.last.cursor : null,
    );
  }

  @override
  Future<void> delete(HistoryTargetKey target) async {
    if (failDelete) {
      throw StateError('delete failed');
    }
    if (_entries.remove(target) != null) {
      _changes.add(
        HistoryChange(kind: HistoryChangeKind.deleted, target: target),
      );
    }
  }

  @override
  Future<void> clear() async {
    if (failClear) {
      throw StateError('clear failed');
    }
    if (_entries.isNotEmpty) {
      _entries.clear();
      _changes.add(const HistoryChange(kind: HistoryChangeKind.cleared));
    }
  }

  @override
  Future<void> restore(HistoryEntry entry) async {
    if (failRestore) {
      throw StateError('restore failed');
    }
    final existing = _entries[entry.target];
    if (existing != null &&
        !entry.lastVisitedAt.isAfter(existing.lastVisitedAt)) {
      return;
    }
    _entries[entry.target] = entry;
    _changes.add(
      HistoryChange(kind: HistoryChangeKind.restored, target: entry.target),
    );
  }

  @override
  Stream<HistoryChange> watchChanges() => _changes.stream;

  Future<void> dispose() => _changes.close();

  bool _isAfterCursor(HistoryEntry entry, HistoryCursor cursor) {
    final timeComparison = entry.lastVisitedAt.compareTo(cursor.lastVisitedAt);
    if (timeComparison != 0) {
      return timeComparison < 0;
    }
    final typeComparison = entry.target.type.name.compareTo(
      cursor.targetType.name,
    );
    if (typeComparison != 0) {
      return typeComparison > 0;
    }
    return entry.target.id.compareTo(cursor.targetId) > 0;
  }
}

HistoryController buildHistoryController(
  MemoryHistoryRepository repository, {
  int pageSize = 50,
  Duration searchDebounce = Duration.zero,
}) {
  const normalizer = HistoryVisitDraftNormalizer();
  return HistoryController(
    repository: repository,
    queryHistory: QueryHistoryUseCase(
      repository: repository,
      normalizer: normalizer,
    ),
    deleteHistoryEntry: DeleteHistoryEntryUseCase(repository),
    restoreHistoryEntry: RestoreHistoryEntryUseCase(repository),
    clearHistory: ClearHistoryUseCase(repository),
    pageSize: pageSize,
    searchDebounce: searchDebounce,
  );
}

HistoryEntry historyEntry({
  required HistoryTargetType type,
  required String id,
  required String title,
  required DateTime visitedAt,
  String contextLabel = '详情',
  HistoryThumbnailSnapshot? thumbnail,
  String? sourceTid,
  int? page,
  String? forumName,
}) {
  final surface = switch (type) {
    HistoryTargetType.thread => HistoryVisitSurface.threadNative,
    HistoryTargetType.comic => HistoryVisitSurface.comicDetail,
    HistoryTargetType.novel => HistoryVisitSurface.novelDetail,
  };
  return HistoryEntry(
    target: HistoryTargetKey(type: type, id: id),
    title: title,
    contextLabel: contextLabel,
    thumbnail: thumbnail,
    sourceTid: sourceTid,
    lastPage: page,
    forumName: forumName,
    lastSurface: surface,
    firstVisitedAt: visitedAt,
    lastVisitedAt: visitedAt,
    visitCount: 1,
  );
}

int compareHistoryEntries(HistoryEntry a, HistoryEntry b) {
  final byTime = b.lastVisitedAt.compareTo(a.lastVisitedAt);
  if (byTime != 0) {
    return byTime;
  }
  final byType = a.target.type.name.compareTo(b.target.type.name);
  return byType != 0 ? byType : a.target.id.compareTo(b.target.id);
}
