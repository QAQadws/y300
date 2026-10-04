import 'package:sqflite/sqflite.dart';

import '../app_database_tables.dart';
import 'migration_helpers.dart';

/// Phase 0: 为小说模块预留统一内容表与阅读偏好表。
///
/// 这一批表暂不与现有漫画流程耦合，先完成数据库地基与索引建设，
/// 便于后续按阶段接入仓储与页面逻辑。
Future<void> createNovelTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $worksTable (
        work_id TEXT PRIMARY KEY,
        content_type TEXT NOT NULL,
        source_tid TEXT NOT NULL,
        source_fid TEXT NOT NULL,
        source_typeid TEXT,
        source_tag_name TEXT,
        title TEXT NOT NULL,
        custom_title TEXT,
        author TEXT,
        cover_image_url TEXT,
        cover_local_path TEXT,
        custom_cover_local_path TEXT,
        cover_revision INTEGER NOT NULL DEFAULT 0,
        custom_cover_revision INTEGER NOT NULL DEFAULT 0,
        custom_cover_focus_x REAL,
        custom_cover_focus_y REAL,
        cover_hidden INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $workEpisodesTable (
        episode_id TEXT PRIMARY KEY,
        work_id TEXT NOT NULL,
        content_type TEXT NOT NULL,
        source_tid TEXT NOT NULL,
        source_pid TEXT,
        source_page INTEGER,
        episode_title TEXT,
        order_index INTEGER NOT NULL,
        dateline_text TEXT,
        FOREIGN KEY (work_id) REFERENCES $worksTable(work_id) ON DELETE CASCADE
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelEpisodeContentTable (
        episode_id TEXT PRIMARY KEY,
        raw_html TEXT NOT NULL,
        plain_text TEXT NOT NULL,
        paragraph_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (episode_id) REFERENCES $workEpisodesTable(episode_id) ON DELETE CASCADE
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $readerPreferencesTable (
        content_type TEXT PRIMARY KEY,
        font_size REAL NOT NULL,
        line_height REAL NOT NULL,
        paragraph_spacing REAL NOT NULL,
        page_padding REAL NOT NULL,
        theme_mode TEXT NOT NULL,
        font_family TEXT,
        flow_mode TEXT,
        theme_preset TEXT,
        content_max_width REAL,
        first_line_indent REAL,
        font_weight INTEGER,
        text_align TEXT,
        show_progress_indicator INTEGER,
        show_chapter_title INTEGER,
        conversion_mode TEXT
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_work_type_updated ON $worksTable(content_type, updated_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_episode_work_order ON $workEpisodesTable(work_id, order_index ASC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_episode_tid_pid ON $workEpisodesTable(source_tid, source_pid)',
  );
}

Future<void> createNovelReadingProgressTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelReadingProgressTable (
        novel_id TEXT PRIMARY KEY,
        episode_id TEXT NOT NULL,
        scroll_offset REAL NOT NULL,
        flow_mode TEXT,
        page_index INTEGER,
        page_count INTEGER,
        anchor_node_id TEXT,
        anchor_text_offset INTEGER NOT NULL DEFAULT 0,
        pagination_key TEXT,
        progress_percent REAL,
        anchor_format_version INTEGER NOT NULL DEFAULT 0,
        anchor_text_identity TEXT,
        progress_percent_valid INTEGER,
        updated_at INTEGER NOT NULL
      )
    ''');
}

Future<void> createNovelHydrationTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelSourceStateTable (
        novel_id TEXT PRIMARY KEY,
        publisher_id TEXT,
        publisher_name TEXT,
        first_post_pid TEXT,
        source_intro TEXT,
        source_catalog_json TEXT NOT NULL DEFAULT '[]',
        metadata_source_version INTEGER,
        hydration_state TEXT NOT NULL DEFAULT 'metadataOnly',
        metadata_ingested_at INTEGER,
        chapters_hydrated_at INTEGER,
        last_completed_author_page INTEGER NOT NULL DEFAULT 0,
        last_seen_pid TEXT,
        last_sync_at INTEGER,
        last_error TEXT,
        FOREIGN KEY (novel_id) REFERENCES $worksTable(work_id) ON DELETE CASCADE
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelEpisodeSyncStagingTable (
        run_id TEXT NOT NULL,
        novel_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        source_tid TEXT NOT NULL,
        source_pid TEXT NOT NULL,
        author_filtered_page INTEGER NOT NULL,
        episode_title TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        dateline_text TEXT,
        raw_html TEXT NOT NULL,
        plain_text TEXT NOT NULL,
        paragraph_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (run_id, episode_id)
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_novel_episode_stage_run ON '
    '$novelEpisodeSyncStagingTable(run_id, order_index)',
  );
}

Future<void> backfillLegacyNovelSourceState(Database db) async {
  await db.execute('''
      INSERT OR IGNORE INTO $novelSourceStateTable (
        novel_id,
        publisher_name,
        source_catalog_json,
        hydration_state,
        last_completed_author_page
      )
      SELECT
        work.work_id,
        NULLIF(TRIM(work.author), ''),
        '[]',
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM $workEpisodesTable episode
            WHERE episode.work_id = work.work_id
              AND episode.content_type = 'novel'
          ) THEN 'legacyNeedsRebuild'
          ELSE 'metadataOnly'
        END,
        0
      FROM $worksTable work
      WHERE work.content_type = 'novel'
    ''');
}

Future<void> createNovelReaderBookmarksTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $readerBookmarksTable (
        bookmark_id TEXT PRIMARY KEY,
        novel_id TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        node_id TEXT,
        text_offset INTEGER NOT NULL DEFAULT 0,
        page_index INTEGER NOT NULL DEFAULT 0,
        scroll_offset REAL NOT NULL DEFAULT 0,
        progress_percent REAL NOT NULL DEFAULT 0,
        anchor_format_version INTEGER NOT NULL DEFAULT 0,
        anchor_text_identity TEXT,
        progress_percent_valid INTEGER,
        title TEXT NOT NULL,
        snippet TEXT NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (novel_id) REFERENCES $worksTable(work_id) ON DELETE CASCADE,
        FOREIGN KEY (episode_id) REFERENCES $workEpisodesTable(episode_id) ON DELETE CASCADE
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_reader_bookmarks_novel_episode ON '
    '$readerBookmarksTable(novel_id, episode_id, created_at)',
  );
}

/// Phase 1.2: 小说书架分类体系，和漫画分类能力对齐。
Future<void> createNovelShelfTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelCategoriesTable (
        category_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelShelfItemsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id TEXT NOT NULL,
        novel_id TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        UNIQUE(category_id, novel_id),
        FOREIGN KEY (category_id) REFERENCES $novelCategoriesTable(category_id) ON DELETE CASCADE,
        FOREIGN KEY (novel_id) REFERENCES $worksTable(work_id) ON DELETE CASCADE
      )
    ''');

  await db.insert(novelCategoriesTable, <String, Object?>{
    'category_id': 'default',
    'name': '默认',
    'sort_order': 0,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_novel_shelf_items_category_sort ON $novelShelfItemsTable(category_id, sort_order)',
  );
}

Future<void> upgradeNovelFrom28To29(Database db) async {
  await createNovelHydrationTables(db);
  await backfillLegacyNovelSourceState(db);
}

Future<void> upgradeNovelFrom29To30(Database db) async {
  await addColumnIfMissing(
    db,
    table: worksTable,
    column: 'custom_title',
    definition: 'TEXT',
  );
  await addColumnIfMissing(
    db,
    table: worksTable,
    column: 'custom_cover_focus_x',
    definition: 'REAL',
  );
  await addColumnIfMissing(
    db,
    table: worksTable,
    column: 'custom_cover_focus_y',
    definition: 'REAL',
  );
}

Future<void> upgradeNovelFrom30To31(Database db) async {
  await addColumnIfMissing(
    db,
    table: worksTable,
    column: 'cover_hidden',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
}

Future<void> upgradeNovelFrom33To34(Database db) async {
  await addColumnIfMissing(
    db,
    table: novelReadingProgressTable,
    column: 'pagination_key',
    definition: 'TEXT',
  );
  await addColumnIfMissing(
    db,
    table: novelReadingProgressTable,
    column: 'anchor_text_offset',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
}

Future<void> upgradeNovelFrom34To35(Database db) async {
  await addColumnIfMissing(
    db,
    table: novelReadingProgressTable,
    column: 'page_count',
    definition: 'INTEGER',
  );
}

Future<void> upgradeNovelFrom41To42(Database db) async {
  for (final table in <String>[
    novelReadingProgressTable,
    readerBookmarksTable,
  ]) {
    await addColumnIfMissing(
      db,
      table: table,
      column: 'anchor_format_version',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumnIfMissing(
      db,
      table: table,
      column: 'anchor_text_identity',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      table: table,
      column: 'progress_percent_valid',
      definition: 'INTEGER',
    );
  }
}
