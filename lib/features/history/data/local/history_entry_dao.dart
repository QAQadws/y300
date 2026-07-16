import 'package:sqflite/sqflite.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/history/data/local/history_row_mapper.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

class HistoryEntryDao {
  const HistoryEntryDao({HistoryRowMapper mapper = const HistoryRowMapper()})
    : _mapper = mapper;

  final HistoryRowMapper _mapper;

  Future<void> upsertVisit(DatabaseExecutor db, HistoryEntry candidate) async {
    final row = _mapper.toRow(candidate);
    await db.rawInsert('''
      INSERT INTO ${HistoryLocalDb.entriesTable} (
        target_type,
        target_id,
        title,
        context_label,
        thumbnail_local_path,
        thumbnail_remote_url,
        thumbnail_focus_x,
        thumbnail_focus_y,
        source_tid,
        canonical_url,
        last_page,
        forum_name,
        last_surface,
        first_visited_at,
        last_visited_at,
        visit_count
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(target_type, target_id) DO UPDATE SET
        title = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN excluded.title ELSE title END,
        context_label = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN excluded.context_label ELSE context_label END,
        thumbnail_local_path = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.thumbnail_local_path, thumbnail_local_path)
          ELSE thumbnail_local_path END,
        thumbnail_remote_url = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.thumbnail_remote_url, thumbnail_remote_url)
          ELSE thumbnail_remote_url END,
        thumbnail_focus_x = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.thumbnail_focus_x, thumbnail_focus_x)
          ELSE thumbnail_focus_x END,
        thumbnail_focus_y = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.thumbnail_focus_y, thumbnail_focus_y)
          ELSE thumbnail_focus_y END,
        source_tid = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.source_tid, source_tid)
          ELSE source_tid END,
        canonical_url = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.canonical_url, canonical_url)
          ELSE canonical_url END,
        last_page = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.last_page, last_page)
          ELSE last_page END,
        forum_name = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN COALESCE(excluded.forum_name, forum_name)
          ELSE forum_name END,
        last_surface = CASE
          WHEN excluded.last_visited_at >= last_visited_at
          THEN excluded.last_surface ELSE last_surface END,
        first_visited_at = MIN(first_visited_at, excluded.first_visited_at),
        last_visited_at = MAX(last_visited_at, excluded.last_visited_at),
        visit_count = visit_count + 1
      ''', _values(row));
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

  List<Object?> _values(Map<String, Object?> row) {
    return <Object?>[
      row['target_type'],
      row['target_id'],
      row['title'],
      row['context_label'],
      row['thumbnail_local_path'],
      row['thumbnail_remote_url'],
      row['thumbnail_focus_x'],
      row['thumbnail_focus_y'],
      row['source_tid'],
      row['canonical_url'],
      row['last_page'],
      row['forum_name'],
      row['last_surface'],
      row['first_visited_at'],
      row['last_visited_at'],
      row['visit_count'],
    ];
  }

  String _escapeLike(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }
}
