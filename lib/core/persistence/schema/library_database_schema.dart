import 'package:sqflite/sqflite.dart';

import '../app_database_tables.dart';
import 'migration_helpers.dart';

/// Phase 1: 统一状态表（未读/下载/书签/标签/显示配置）。
Future<void> createLibraryStateTables(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $libraryWorkStateTable (
        content_type TEXT NOT NULL,
        work_id TEXT NOT NULL,
        last_read_episode_id TEXT,
        last_read_at INTEGER,
        check_updated_at INTEGER,
        fetched_updated_at INTEGER,
        intro_text TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (content_type, work_id)
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $libraryEpisodeStateTable (
        content_type TEXT NOT NULL,
        episode_id TEXT NOT NULL,
        work_id TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_downloaded INTEGER NOT NULL DEFAULT 0,
        is_bookmarked INTEGER NOT NULL DEFAULT 0,
        read_at INTEGER,
        downloaded_at INTEGER,
        PRIMARY KEY (content_type, episode_id)
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $libraryTagsTable (
        tag_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $libraryWorkTagsTable (
        content_type TEXT NOT NULL,
        work_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        UNIQUE(content_type, work_id, tag_id),
        FOREIGN KEY (tag_id) REFERENCES $libraryTagsTable(tag_id) ON DELETE CASCADE
      )
    ''');

  await db.execute('''
      CREATE TABLE IF NOT EXISTS $libraryDisplaySettingsTable (
        module_key TEXT PRIMARY KEY,
        display_mode TEXT NOT NULL,
        grid_columns INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_library_episode_state_work_read ON $libraryEpisodeStateTable(content_type, work_id, is_read)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_library_episode_state_work_downloaded ON $libraryEpisodeStateTable(content_type, work_id, is_downloaded)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_library_work_tags_work ON $libraryWorkTagsTable(content_type, work_id)',
  );
}

/// Phase 7：针对统一书架/详情的高频筛选与排序路径补充索引。
Future<void> createLibraryPerformanceIndexes(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_library_episode_state_work_bookmarked ON '
    '$libraryEpisodeStateTable(content_type, work_id, is_bookmarked)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_work_episodes_type_work_order ON '
    '$workEpisodesTable(content_type, work_id, order_index)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_episodes_comic_order ON '
    '$episodesTable(comic_id, order_index)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_shelf_items_comic ON '
    '$shelfItemsTable(comic_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_novel_shelf_items_novel ON '
    '$novelShelfItemsTable(novel_id)',
  );
}

Future<void> createLibraryCoverMigrationTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS $libraryCoverMigrationsTable (
        asset_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        kind TEXT NOT NULL,
        completed_at INTEGER NOT NULL,
        PRIMARY KEY (asset_id, revision)
      )
    ''');
}

Future<void> createLibraryCoverRevisionTriggers(Database db) async {
  final comicColumns = await columnNames(db, comicsTable);
  if (comicColumns.containsAll(const <String>{
    'comic_id',
    'cover_image_url',
    'cover_local_path',
    'cover_revision',
  })) {
    await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_comics_cover_revision_update
        AFTER UPDATE OF cover_image_url ON $comicsTable
        WHEN OLD.cover_image_url IS NOT NEW.cover_image_url
        BEGIN
          UPDATE $comicsTable
          SET cover_revision = CASE
            WHEN NEW.cover_image_url IS NULL AND NEW.cover_local_path IS NULL THEN 0
            ELSE OLD.cover_revision + 1
          END
          WHERE comic_id = NEW.comic_id;
        END
      ''');
    await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_comics_cover_revision_insert
        AFTER INSERT ON $comicsTable
        WHEN NEW.cover_revision = 0
          AND (NEW.cover_image_url IS NOT NULL OR NEW.cover_local_path IS NOT NULL)
        BEGIN
          UPDATE $comicsTable SET cover_revision = 1
          WHERE comic_id = NEW.comic_id;
        END
      ''');
  }

  final workColumns = await columnNames(db, worksTable);
  if (workColumns.containsAll(const <String>{
    'work_id',
    'cover_image_url',
    'cover_local_path',
    'cover_revision',
  })) {
    await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_works_cover_revision_update
        AFTER UPDATE OF cover_image_url ON $worksTable
        WHEN OLD.cover_image_url IS NOT NEW.cover_image_url
        BEGIN
          UPDATE $worksTable
          SET cover_revision = CASE
            WHEN NEW.cover_image_url IS NULL AND NEW.cover_local_path IS NULL THEN 0
            ELSE OLD.cover_revision + 1
          END
          WHERE work_id = NEW.work_id;
        END
      ''');
    await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_works_cover_revision_insert
        AFTER INSERT ON $worksTable
        WHEN NEW.cover_revision = 0
          AND (NEW.cover_image_url IS NOT NULL OR NEW.cover_local_path IS NOT NULL)
        BEGIN
          UPDATE $worksTable SET cover_revision = 1
          WHERE work_id = NEW.work_id;
        END
      ''');
  }
}

Future<void> upgradeLibraryFrom38To39(Database db) async {
  await addColumnIfMissing(
    db,
    table: comicsTable,
    column: 'cover_revision',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
  await addColumnIfMissing(
    db,
    table: comicsTable,
    column: 'custom_cover_revision',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
  await addColumnIfMissing(
    db,
    table: worksTable,
    column: 'cover_revision',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
  await addColumnIfMissing(
    db,
    table: worksTable,
    column: 'custom_cover_revision',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
  await backfillCoverRevision(
    db,
    table: comicsTable,
    revisionColumn: 'cover_revision',
    sourceColumns: const <String>['cover_image_url', 'cover_local_path'],
  );
  await backfillCoverRevision(
    db,
    table: comicsTable,
    revisionColumn: 'custom_cover_revision',
    sourceColumns: const <String>[
      'custom_cover_image_url',
      'custom_cover_local_path',
    ],
  );
  await backfillCoverRevision(
    db,
    table: worksTable,
    revisionColumn: 'cover_revision',
    sourceColumns: const <String>['cover_image_url', 'cover_local_path'],
  );
  await backfillCoverRevision(
    db,
    table: worksTable,
    revisionColumn: 'custom_cover_revision',
    sourceColumns: const <String>['custom_cover_local_path'],
  );
  await createLibraryCoverMigrationTable(db);
  await createLibraryCoverRevisionTriggers(db);
}
