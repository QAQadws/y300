import 'package:sqflite/sqflite.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/history/data/local/history_row_mapper.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

class HistoryEntryDao {
  const HistoryEntryDao({HistoryRowMapper mapper = const HistoryRowMapper()})
    : _mapper = mapper;

  final HistoryRowMapper _mapper;

  Future<void> upsertVisit(Transaction db, HistoryEntry candidate) async {
    final row = _mapper.toRow(candidate);
    // A late visit still increments the count, but cannot replace newer fields.
    const latestFields = <String, bool>{
      'title': false,
      'context_label': false,
      'thumbnail_local_path': true,
      'thumbnail_remote_url': true,
      'thumbnail_focus_x': true,
      'thumbnail_focus_y': true,
      'source_tid': true,
      'canonical_url': true,
      'last_page': true,
      'forum_name': true,
      'last_surface': false,
    };
    final assignments = <String>[];
    final arguments = <Object?>[];
    for (final field in latestFields.entries) {
      final column = field.key;
      final replacement = field.value ? 'COALESCE(?, $column)' : '?';
      assignments.add(
        '$column = CASE WHEN ? >= last_visited_at '
        'THEN $replacement ELSE $column END',
      );
      arguments.addAll(<Object?>[row['last_visited_at'], row[column]]);
    }
    assignments.addAll(const <String>[
      'first_visited_at = MIN(first_visited_at, ?)',
      'last_visited_at = MAX(last_visited_at, ?)',
      'visit_count = visit_count + 1',
    ]);
    arguments.addAll(<Object?>[
      row['first_visited_at'],
      row['last_visited_at'],
      row['target_type'],
      row['target_id'],
    ]);
    final updated = await db.rawUpdate(
      'UPDATE ${HistoryLocalDb.entriesTable} SET ${assignments.join(', ')} '
      'WHERE target_type = ? AND target_id = ?',
      arguments,
    );
    if (updated == 0) {
      await db.insert(HistoryLocalDb.entriesTable, row);
    }
  }

  Future<HistoryQueryPage> query(
    DatabaseExecutor db,
    HistoryQuery query,
  ) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (query.targetTypes.isNotEmpty) {
      final orderedTypes = query.targetTypes.toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));
      clauses.add(
        'target_type IN (${List.filled(orderedTypes.length, '?').join(', ')})',
      );
      arguments.addAll(orderedTypes.map(_mapper.encodeTargetType));
    }

    if (query.searchText.isNotEmpty) {
      final pattern = '%${_escapeLike(query.searchText)}%';
      clauses.add('''
        (
          title LIKE ? ESCAPE '\\' OR
          context_label LIKE ? ESCAPE '\\' OR
          forum_name LIKE ? ESCAPE '\\' OR
          target_id LIKE ? ESCAPE '\\'
        )
      ''');
      arguments.addAll(<Object?>[pattern, pattern, pattern, pattern]);
    }

    final cursor = query.cursor;
    if (cursor != null) {
      final cursorTime = cursor.lastVisitedAt.toUtc().millisecondsSinceEpoch;
      final cursorType = _mapper.encodeTargetType(cursor.targetType);
      clauses.add('''
        (
          last_visited_at < ? OR
          (last_visited_at = ? AND target_type > ?) OR
          (last_visited_at = ? AND target_type = ? AND target_id > ?)
        )
      ''');
      arguments.addAll(<Object?>[
        cursorTime,
        cursorTime,
        cursorType,
        cursorTime,
        cursorType,
        cursor.targetId,
      ]);
    }

    final rows = await db.query(
      HistoryLocalDb.entriesTable,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'last_visited_at DESC, target_type ASC, target_id ASC',
      limit: query.limit + 1,
    );
    final hasMore = rows.length > query.limit;
    final visibleRows = hasMore ? rows.take(query.limit) : rows;
    final items = visibleRows.map(_mapper.fromRow).toList(growable: false);
    return HistoryQueryPage(
      items: items,
      hasMore: hasMore,
      nextCursor: hasMore && items.isNotEmpty ? items.last.cursor : null,
    );
  }

  Future<int> delete(DatabaseExecutor db, HistoryTargetKey target) {
    return db.delete(
      HistoryLocalDb.entriesTable,
      where: 'target_type = ? AND target_id = ?',
      whereArgs: <Object?>[_mapper.encodeTargetType(target.type), target.id],
    );
  }

  Future<int> clear(DatabaseExecutor db) {
    return db.delete(HistoryLocalDb.entriesTable);
  }

  Future<int> restore(DatabaseExecutor db, HistoryEntry entry) {
    return _restore(db, entry);
  }

  Future<int> _restore(DatabaseExecutor db, HistoryEntry entry) async {
    final row = _mapper.toRow(entry);
    final existing = await db.query(
      HistoryLocalDb.entriesTable,
      columns: const <String>['last_visited_at'],
      where: 'target_type = ? AND target_id = ?',
      whereArgs: <Object?>[row['target_type'], row['target_id']],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingTime = existing.first['last_visited_at'];
      if (existingTime is num &&
          existingTime.toInt() >= entry.lastVisitedAt.millisecondsSinceEpoch) {
        return 0;
      }
    }
    await db.insert(
      HistoryLocalDb.entriesTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return 1;
  }

  Future<int> prune(DatabaseExecutor db, {required int maxEntries}) {
    return db.rawDelete(
      '''
      DELETE FROM ${HistoryLocalDb.entriesTable}
      WHERE rowid IN (
        SELECT rowid
        FROM ${HistoryLocalDb.entriesTable}
        ORDER BY last_visited_at DESC, target_type ASC, target_id ASC
        LIMIT -1 OFFSET ?
      )
      ''',
      <Object?>[maxEntries],
    );
  }

  String _escapeLike(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }
}
