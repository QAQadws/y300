import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/data/repositories/local/favorite_cache_row_mapper.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

/// Owns favorite thread and sync-state persistence on the shared connection.
class FavoriteSyncStore {
  const FavoriteSyncStore(this._dbFuture);

  final Future<Database> _dbFuture;

  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.favoriteSyncStateTable,
      where: 'sync_key = ?',
      whereArgs: <Object>[favoriteSyncKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return FavoriteCacheRowMapper.syncSnapshot(rows.first);
  }

  Future<int> countActiveThreads() async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM ${AppDatabase.favoriteThreadsTable}
      WHERE removed_at IS NULL
      ''');
    return rows.first['count'] as int? ?? 0;
  }

  Future<int> countMissingDetailRecords() async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM ${AppDatabase.favoriteThreadsTable}
      WHERE removed_at IS NULL
        AND detail_state = 'pending'
      ''');
    return rows.first['count'] as int? ?? 0;
  }

  Future<Set<String>> getActiveTids() async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.favoriteThreadsTable,
      columns: <String>['tid'],
      where: 'removed_at IS NULL',
    );
    return rows.map((row) => row['tid'] as String).toSet();
  }

  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.favoriteThreadsTable,
      where: 'removed_at IS NULL',
      orderBy: 'remote_order ASC, last_seen_at DESC',
    );
    return rows.map(FavoriteCacheRowMapper.record).toList(growable: false);
  }

  Future<bool> hasCompletedComicAutoRefreshBackfill() async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.favoriteSyncStateTable,
      columns: const <String>['status'],
      where: 'sync_key = ?',
      whereArgs: const <Object>[favoriteComicAutoRefreshBackfillSyncKey],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['status'] == 'ok';
  }

  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      AppDatabase.favoriteSyncStateTable,
      <String, Object?>{
        'sync_key': favoriteComicAutoRefreshBackfillSyncKey,
        'remote_count': checkedCount,
        'local_active_count': await countActiveThreads(),
        'last_synced_at': now,
        'last_full_synced_at': now,
        'status': 'ok',
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final localActiveCount = await countActiveThreads();
    final old = await getSyncSnapshot();

    await db.insert(
      AppDatabase.favoriteSyncStateTable,
      <String, Object?>{
        'sync_key': favoriteSyncKey,
        'remote_count': remoteCount,
        'local_active_count': localActiveCount,
        'last_synced_at': now,
        'last_full_synced_at': mode == FavoriteSyncMode.fullDiff
            ? now
            : old?.lastFullSyncedAt?.millisecondsSinceEpoch,
        'status': status ?? 'ok',
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markSyncFailure(String message) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await getSyncSnapshot();
    await db.insert(
      AppDatabase.favoriteSyncStateTable,
      <String, Object?>{
        'sync_key': favoriteSyncKey,
        'remote_count': old?.remoteCount ?? 0,
        'local_active_count': await countActiveThreads(),
        'last_synced_at': old?.lastSyncedAt?.millisecondsSinceEpoch,
        'last_full_synced_at': old?.lastFullSyncedAt?.millisecondsSinceEpoch,
        'status': 'failed',
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.update(
      AppDatabase.favoriteSyncStateTable,
      <String, Object?>{'last_synced_at': now},
      where: 'sync_key = ?',
      whereArgs: <Object>[favoriteSyncKey],
    );
  }

  Future<int> upsertRemoteThreads(List<FavoriteThreadCacheUpsert> items) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = 0;

    await db.transaction((txn) async {
      for (final item in items) {
        final tid = item.tid.trim();
        if (tid.isEmpty) {
          continue;
        }

        final oldRows = await txn.query(
          AppDatabase.favoriteThreadsTable,
          where: 'tid = ?',
          whereArgs: <Object>[tid],
          limit: 1,
        );
        final old = oldRows.isEmpty ? null : oldRows.first;
        final firstSeenAt = (old?['first_seen_at'] as int?) ?? now;

        final values = <String, Object?>{
          'tid': tid,
          'favid': FavoriteCacheRowMapper.normalizeNullable(
            item.remoteFavoriteId,
          ),
          'title': FavoriteCacheRowMapper.nonEmpty(
            item.title,
            fallback: '未命名收藏',
          ),
          'description': FavoriteCacheRowMapper.normalizeNullable(
            item.description,
          ),
          'author': FavoriteCacheRowMapper.normalizeNullable(item.authorName),
          'replies': item.replyCount,
          'url': null,
          'dateline': item.favoritedAt?.millisecondsSinceEpoch == null
              ? null
              : item.favoritedAt!.millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
          'remote_order': item.remoteOrder,
          'first_seen_at': firstSeenAt,
          'last_seen_at': now,
          'removed_at': null,
        };

        if (old == null) {
          await txn.insert(AppDatabase.favoriteThreadsTable, <String, Object?>{
            ...values,
            'source_fid': null,
            'source_typeid': null,
            'source_tag_name': null,
            'content_kind': 'unknown',
            'work_id': null,
            'detail_loaded_at': null,
            'detail_state': favoriteDetailStateToDb(
              FavoriteDetailState.pending,
            ),
          });
        } else {
          await txn.update(
            AppDatabase.favoriteThreadsTable,
            values,
            where: 'tid = ?',
            whereArgs: <Object>[tid],
          );
        }
        changed++;
      }
    });

    return changed;
  }

  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    final db = await _dbFuture;
    final queryLimit = limit + excludedTids.length;
    final rows = await db.rawQuery(
      '''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
        AND ft.detail_state = 'pending'
      ORDER BY ft.remote_order ASC, ft.last_seen_at DESC
      LIMIT ?
      ''',
      <Object>[queryLimit],
    );
    return rows
        .map(FavoriteCacheRowMapper.record)
        .where((record) => !excludedTids.contains(record.tid))
        .take(limit)
        .toList(growable: false);
  }

  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    final db = await _dbFuture;
    final queryLimit = limit + excludedTids.length;
    final rows = await db.rawQuery(
      '''
      SELECT
        ft.*,
        fc.category_id AS custom_category_id,
        COUNT(e.episode_id) AS episode_count,
        SUM(CASE WHEN e.source_tid = ft.tid THEN 1 ELSE 0 END) AS current_tid_count
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      LEFT JOIN ${AppDatabase.episodesTable} e
        ON e.comic_id = ft.work_id
      WHERE ft.removed_at IS NULL
        AND ft.content_kind = 'comic'
        AND ft.work_id IS NOT NULL
        AND TRIM(ft.work_id) <> ''
      GROUP BY ft.tid
      HAVING episode_count = 0
        OR (episode_count = 1 AND current_tid_count = 1)
      ORDER BY ft.remote_order ASC, ft.last_seen_at DESC
      LIMIT ?
      ''',
      <Object>[queryLimit],
    );
    return rows
        .map(FavoriteCacheRowMapper.record)
        .where((record) => !excludedTids.contains(record.tid))
        .take(limit)
        .toList(growable: false);
  }

  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {
    final db = await _dbFuture;
    await db.update(
      AppDatabase.favoriteThreadsTable,
      <String, Object?>{
        'source_fid': FavoriteCacheRowMapper.normalizeNullable(fid),
        'source_typeid': FavoriteCacheRowMapper.normalizeNullable(typeid),
        'source_tag_name': FavoriteCacheRowMapper.normalizeNullable(tagName),
        'content_kind': favoriteContentKindToDb(contentKind),
        'work_id': FavoriteCacheRowMapper.normalizeNullable(workId),
        'detail_loaded_at': DateTime.now().millisecondsSinceEpoch,
        'detail_state': favoriteDetailStateToDb(FavoriteDetailState.resolved),
      },
      where: 'tid = ?',
      whereArgs: <Object>[tid.trim()],
    );
  }

  Future<void> markThreadDetailInvalid({required String tid}) async {
    final db = await _dbFuture;
    await db.update(
      AppDatabase.favoriteThreadsTable,
      <String, Object?>{
        'source_fid': null,
        'source_typeid': null,
        'source_tag_name': null,
        'content_kind': favoriteContentKindToDb(ThreadContentKind.unknown),
        'work_id': null,
        'detail_loaded_at': DateTime.now().millisecondsSinceEpoch,
        'detail_state': favoriteDetailStateToDb(FavoriteDetailState.invalid),
      },
      where: 'tid = ?',
      whereArgs: <Object>[tid.trim()],
    );
  }

  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async {
    final db = await _dbFuture;
    final activeRows = await db.rawQuery('''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
      ''');
    final removed = activeRows
        .map(FavoriteCacheRowMapper.record)
        .where((record) => !activeRemoteTids.contains(record.tid))
        .toList(growable: false);
    if (removed.isEmpty) {
      return removed;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final record in removed) {
        await txn.update(
          AppDatabase.favoriteThreadsTable,
          <String, Object?>{'removed_at': now},
          where: 'tid = ?',
          whereArgs: <Object>[record.tid],
        );
      }
    });
    return removed;
  }

  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.tid = ? AND ft.removed_at IS NULL
      LIMIT 1
      ''',
      <Object>[tid.trim()],
    );
    if (rows.isEmpty) {
      return null;
    }
    return FavoriteCacheRowMapper.record(rows.first);
  }

  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async {
    final normalized = workId.trim();
    if (normalized.isEmpty) {
      return const <FavoriteThreadCacheRecord>[];
    }
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.work_id = ? AND ft.removed_at IS NULL
      ORDER BY ft.remote_order IS NULL, ft.remote_order, ft.tid
      ''',
      <Object>[normalized],
    );
    return rows.map(FavoriteCacheRowMapper.record).toList(growable: false);
  }

  Future<bool> hasActiveThreadForWorkId(String workId) async {
    final normalized = workId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM ${AppDatabase.favoriteThreadsTable}
      WHERE work_id = ? AND removed_at IS NULL
      LIMIT 1
      ''',
      <Object>[normalized],
    );
    return rows.isNotEmpty;
  }

  Future<int> markRemovedByWorkId(String workId) async {
    final normalized = workId.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      AppDatabase.favoriteThreadsTable,
      <String, Object?>{'removed_at': now},
      where: 'work_id = ? AND removed_at IS NULL',
      whereArgs: <Object>[normalized],
    );
  }

  Future<int> markRemovedByTids(Set<String> tids) async {
    final normalized = tids
        .map((tid) => tid.trim())
        .where((tid) => tid.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) {
      return 0;
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final placeholders = List<String>.filled(normalized.length, '?').join(', ');
    return db.update(
      AppDatabase.favoriteThreadsTable,
      <String, Object?>{'removed_at': now},
      where: 'tid IN ($placeholders) AND removed_at IS NULL',
      whereArgs: normalized.toList(growable: false),
    );
  }
}
