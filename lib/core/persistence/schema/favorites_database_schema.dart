import 'package:sqflite/sqflite.dart';

import '../app_database_tables.dart';
import 'migration_helpers.dart';

/// Phase 03：收藏线程缓存与收藏页自定义分类。
///
/// 收藏是漫画/小说同步入口，但数据表保持独立，避免收藏页状态和
/// 漫画/小说书架分类互相污染。
Future<void> createFavoriteTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $favoriteSyncStateTable (
        sync_key TEXT PRIMARY KEY,
        remote_count INTEGER NOT NULL DEFAULT 0,
        local_active_count INTEGER NOT NULL DEFAULT 0,
        last_synced_at INTEGER,
        last_full_synced_at INTEGER,
        status TEXT,
        message TEXT
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $favoriteThreadsTable (
        tid TEXT PRIMARY KEY,
        favid TEXT,
        title TEXT NOT NULL,
        description TEXT,
        author TEXT,
        replies INTEGER NOT NULL DEFAULT 0,
        url TEXT,
        dateline INTEGER,
        remote_order INTEGER,
        source_fid TEXT,
        source_typeid TEXT,
        source_tag_name TEXT,
        content_kind TEXT NOT NULL DEFAULT 'unknown',
        work_id TEXT,
        detail_loaded_at INTEGER,
        detail_state TEXT NOT NULL DEFAULT 'pending',
        first_seen_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        removed_at INTEGER
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $favoriteCategoriesTable (
        category_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $favoriteThreadCategoryTable (
        tid TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        assigned_at INTEGER NOT NULL,
        FOREIGN KEY (tid) REFERENCES $favoriteThreadsTable(tid) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES $favoriteCategoriesTable(category_id) ON DELETE CASCADE
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_favorite_threads_kind_order ON '
    '$favoriteThreadsTable(content_kind, remote_order)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_favorite_threads_removed ON '
    '$favoriteThreadsTable(removed_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_favorite_thread_category_category ON '
    '$favoriteThreadCategoryTable(category_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_favorite_threads_active_kind_order ON '
    '$favoriteThreadsTable(removed_at, content_kind, remote_order)',
  );
  await createFavoriteDetailStateIndex(db);
}

Future<void> createFavoriteDetailStateIndex(Database db) {
  return db.execute(
    'CREATE INDEX IF NOT EXISTS idx_favorite_threads_active_detail_state_order ON '
    '$favoriteThreadsTable(removed_at, detail_state, remote_order)',
  );
}

Future<void> upgradeFavoritesFrom32To33(Database db) async {
  await addColumnIfMissing(
    db,
    table: favoriteThreadsTable,
    column: 'detail_state',
    definition: "TEXT NOT NULL DEFAULT 'pending'",
  );
  await db.execute('''
      UPDATE $favoriteThreadsTable
      SET detail_state = 'resolved'
      WHERE detail_loaded_at IS NOT NULL
        AND detail_state = 'pending'
    ''');
  await createFavoriteDetailStateIndex(db);
}
