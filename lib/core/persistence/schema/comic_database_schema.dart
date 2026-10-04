import 'package:sqflite/sqflite.dart';

import '../app_database_tables.dart';
import 'migration_helpers.dart';

Future<void> createComicTables(Database db) async {
  await db.execute('''
      CREATE TABLE $comicsTable (
        comic_id TEXT PRIMARY KEY,
        source_tid TEXT NOT NULL,
        source_fid TEXT NOT NULL,
        source_typeid TEXT,
        source_tag_name TEXT,
        title TEXT NOT NULL,
        source_title TEXT,
        custom_title TEXT,
        author TEXT,
        source_author TEXT,
        custom_author TEXT,
        cover_image_url TEXT,
        custom_cover_image_url TEXT,
        cover_local_path TEXT,
        custom_cover_local_path TEXT,
        cover_revision INTEGER NOT NULL DEFAULT 0,
        custom_cover_revision INTEGER NOT NULL DEFAULT 0,
        translation_group TEXT,
        source_translation_group TEXT,
        custom_translation_group TEXT,
        custom_cover_source_episode_id TEXT,
        custom_cover_source_image_index INTEGER,
        custom_cover_source_image_url TEXT,
        custom_cover_focus_x REAL,
        custom_cover_focus_y REAL,
        custom_search_title TEXT,
        metadata_updated_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_read_episode_id TEXT,
        catalog_url TEXT,
        custom_catalog_url TEXT
      )
    ''');

  await db.execute('''
      CREATE TABLE $episodesTable (
        episode_id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        episode_title TEXT,
        source_episode_title TEXT,
        custom_episode_title TEXT,
        source_tid TEXT NOT NULL,
        source_url TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        publish_time_text TEXT,
        is_manual INTEGER NOT NULL DEFAULT 0,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (comic_id) REFERENCES $comicsTable(comic_id) ON DELETE CASCADE
      )
    ''');

  await db.execute('''
      CREATE TABLE $episodeImagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        episode_id TEXT NOT NULL,
        image_url TEXT NOT NULL,
        image_index INTEGER NOT NULL,
        stable_cache_key TEXT,
        last_source_url TEXT,
        local_path TEXT,
        width INTEGER,
        height INTEGER,
        bytes INTEGER NOT NULL DEFAULT 0,
        mime_type TEXT,
        last_accessed_at INTEGER,
        protected INTEGER NOT NULL DEFAULT 0,
        cache_local_path TEXT,
        cache_status TEXT NOT NULL DEFAULT 'none',
        UNIQUE(episode_id, image_index),
        FOREIGN KEY (episode_id) REFERENCES $episodesTable(episode_id) ON DELETE CASCADE
      )
    ''');

  await db.execute('''
      CREATE TABLE $categoriesTable (
        category_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

  await db.execute('''
      CREATE TABLE $shelfItemsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id TEXT NOT NULL,
        comic_id TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        UNIQUE(category_id, comic_id),
        FOREIGN KEY (category_id) REFERENCES $categoriesTable(category_id) ON DELETE CASCADE,
        FOREIGN KEY (comic_id) REFERENCES $comicsTable(comic_id) ON DELETE CASCADE
      )
    ''');

  await db.insert(categoriesTable, {
    'category_id': 'default',
    'name': '默认',
    'sort_order': 0,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });

  await db.execute(
    'CREATE INDEX idx_episodes_comic_id ON $episodesTable(comic_id)',
  );
  await db.execute(
    'CREATE INDEX idx_episode_images_episode_id ON $episodeImagesTable(episode_id)',
  );
  await db.execute(
    'CREATE INDEX idx_shelf_items_category_sort ON $shelfItemsTable(category_id, sort_order)',
  );
}

Future<void> createComicSettingsTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $settingsTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
}

Future<void> seedDefaultComicSettings(Database db) async {
  await db.insert(settingsTable, <String, Object?>{
    'key': 'grid_column_count',
    'value': '3',
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Future<void> createComicReadingProgressTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $readingProgressTable (
        comic_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        image_index INTEGER NOT NULL,
        scroll_offset REAL NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (comic_id, episode_id),
        FOREIGN KEY (comic_id) REFERENCES $comicsTable(comic_id) ON DELETE CASCADE,
        FOREIGN KEY (episode_id) REFERENCES $episodesTable(episode_id) ON DELETE CASCADE
      )
    ''');
  await createComicReadingProgressIndex(db);
}

Future<void> createComicReadingProgressIndex(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_reading_progress_comic_updated '
    'ON $readingProgressTable(comic_id, updated_at DESC)',
  );
}

Future<void> createComicCoverMergeJournalTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $comicCoverMergeOperationsTable (
        operation_id TEXT PRIMARY KEY,
        target_comic_id TEXT NOT NULL,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $comicCoverMergeMembersTable (
        operation_id TEXT NOT NULL,
        source_comic_id TEXT NOT NULL,
        PRIMARY KEY (operation_id, source_comic_id),
        FOREIGN KEY (operation_id)
          REFERENCES $comicCoverMergeOperationsTable(operation_id)
          ON DELETE CASCADE
      )
    ''');
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $comicCoverMergeAssetsTable (
        operation_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        source_comic_id TEXT NOT NULL,
        source_asset_id TEXT NOT NULL,
        source_revision INTEGER NOT NULL,
        target_asset_id TEXT NOT NULL,
        target_revision INTEGER NOT NULL,
        mode TEXT NOT NULL,
        PRIMARY KEY (operation_id, kind),
        FOREIGN KEY (operation_id)
          REFERENCES $comicCoverMergeOperationsTable(operation_id)
          ON DELETE CASCADE
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_comic_cover_merge_state ON '
    '$comicCoverMergeOperationsTable(state, created_at)',
  );
}

/// 收藏自动刷新阶段 3：漫画搜索等待队列。
///
/// 队列表只保存“需要走搜索/当前帖回退”的后台刷新任务；catalog-only
/// 成功的作品不进入这里，避免把立即刷新和搜索冷却调度混在一起。
Future<void> createComicSearchRefreshQueueTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $comicSearchRefreshQueueTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comic_id TEXT NOT NULL,
        source_tid TEXT NOT NULL,
        title TEXT NOT NULL,
        display_title TEXT,
        source_title TEXT,
        custom_title TEXT,
        custom_search_title TEXT,
        origin TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        available_at INTEGER NOT NULL,
        started_at INTEGER,
        completed_at INTEGER,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_comic_search_refresh_queue_active ON '
    '$comicSearchRefreshQueueTable(status, available_at, created_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_comic_search_refresh_queue_comic ON '
    '$comicSearchRefreshQueueTable(comic_id, status)',
  );
}

Future<void> createComicDownloadQueueTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $comicDownloadQueueTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comic_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        comic_title TEXT NOT NULL,
        episode_title TEXT NOT NULL,
        status TEXT NOT NULL,
        completed_images INTEGER NOT NULL DEFAULT 0,
        total_images INTEGER,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(comic_id, episode_id),
        FOREIGN KEY (comic_id) REFERENCES $comicsTable(comic_id) ON DELETE CASCADE,
        FOREIGN KEY (episode_id) REFERENCES $episodesTable(episode_id) ON DELETE CASCADE
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_comic_download_queue_status ON '
    '$comicDownloadQueueTable(status, created_at, id)',
  );
}

Future<void> upgradeComicFrom27To28(Database db) async {
  await db.execute(
    'ALTER TABLE $comicsTable ADD COLUMN custom_catalog_url TEXT',
  );
}

Future<void> upgradeComicFrom31To32(Database db) async {
  const migratedTable = '${readingProgressTable}_v32';
  await db.execute('DROP TABLE IF EXISTS $migratedTable');
  await db.execute('''
      CREATE TABLE $migratedTable (
        comic_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        image_index INTEGER NOT NULL,
        scroll_offset REAL NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (comic_id, episode_id),
        FOREIGN KEY (comic_id) REFERENCES $comicsTable(comic_id) ON DELETE CASCADE,
        FOREIGN KEY (episode_id) REFERENCES $episodesTable(episode_id) ON DELETE CASCADE
      )
    ''');
  await db.execute('''
      INSERT OR REPLACE INTO $migratedTable (
        comic_id, episode_id, image_index, scroll_offset, updated_at
      )
      SELECT progress.comic_id, progress.episode_id, progress.image_index,
             progress.scroll_offset, progress.updated_at
      FROM $readingProgressTable AS progress
      INNER JOIN $episodesTable AS episode
        ON episode.episode_id = progress.episode_id
       AND episode.comic_id = progress.comic_id
    ''');
  await db.execute('DROP TABLE $readingProgressTable');
  await db.execute(
    'ALTER TABLE $migratedTable RENAME TO $readingProgressTable',
  );
  await createComicReadingProgressIndex(db);
}

Future<void> upgradeComicFrom35To36(Database db) async {
  await createComicDownloadQueueTable(db);
}

/// 章节管理：区分“解析章节”与“手动添加章节”，并支持隐藏而不删除。
///
/// 两个标记都落在章节行上而不是独立表：隐藏与来源归属是章节自身属性，
/// 放在同一行才能让读取路径用一次查询同时完成过滤与归属判断。
Future<void> upgradeComicFrom36To37(Database db) async {
  await addColumnIfMissing(
    db,
    table: episodesTable,
    column: 'is_manual',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
  await addColumnIfMissing(
    db,
    table: episodesTable,
    column: 'is_hidden',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
}

/// 章节重命名：拆出「来源章节名」与「用户自定义章节名」两列。
///
/// 与漫画标题同一套三列结构（source / custom / 解析后的展示值）：`episode_title`
/// 继续作为展示值，所有既有读取点不用改。存量行的标题都来自解析，因此直接
/// 回填为来源名——否则清空自定义名后会退成空标题，而不是退回原本的章节名。
Future<void> upgradeComicFrom37To38(Database db) async {
  await addColumnIfMissing(
    db,
    table: episodesTable,
    column: 'source_episode_title',
    definition: 'TEXT',
  );
  await addColumnIfMissing(
    db,
    table: episodesTable,
    column: 'custom_episode_title',
    definition: 'TEXT',
  );
  // 回填读的是 `episode_title`，历史库不保证有这一列（缺表、或早期精简
  // schema），所以按列存在性判断而不是只判断表存在。
  final columns = await columnNames(db, episodesTable);
  if (!columns.contains('episode_title') ||
      !columns.contains('source_episode_title')) {
    return;
  }
  await db.execute('''
      UPDATE $episodesTable
      SET source_episode_title = episode_title
      WHERE source_episode_title IS NULL
    ''');
}

Future<void> upgradeComicFrom39To40(Database db) async {
  await createComicCoverMergeJournalTables(db);
}
