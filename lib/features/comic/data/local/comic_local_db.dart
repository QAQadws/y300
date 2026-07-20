import 'package:sqflite/sqflite.dart';

/// 漫画本地数据库定义与建表逻辑。
class ComicLocalDb {
  ComicLocalDb._();

  static const String dbName = 'comic_shelf.db';
  static const int dbVersion = 34;

  static const String comicsTable = 'comics';
  static const String episodesTable = 'episodes';
  static const String episodeImagesTable = 'episode_images';
  static const String categoriesTable = 'categories';
  static const String shelfItemsTable = 'shelf_items';
  static const String settingsTable = 'settings';
  static const String readingProgressTable = 'reading_progress';
  static const String worksTable = 'works';
  static const String workEpisodesTable = 'work_episodes';
  static const String novelEpisodeContentTable = 'novel_episode_content';
  static const String readerPreferencesTable = 'reader_preferences';
  static const String novelReadingProgressTable = 'novel_reading_progress';
  static const String readerBookmarksTable = 'reader_bookmarks';
  static const String novelCategoriesTable = 'novel_categories';
  static const String novelShelfItemsTable = 'novel_shelf_items';
  static const String libraryWorkStateTable = 'library_work_state';
  static const String libraryEpisodeStateTable = 'library_episode_state';
  static const String libraryTagsTable = 'library_tags';
  static const String libraryWorkTagsTable = 'library_work_tags';
  static const String libraryDisplaySettingsTable = 'library_display_settings';
  static const String favoriteSyncStateTable = 'favorite_sync_state';
  static const String favoriteThreadsTable = 'favorite_threads';
  static const String favoriteCategoriesTable = 'favorite_categories';
  static const String favoriteThreadCategoryTable = 'favorite_thread_category';
  static const String cachedImagesTable = 'cached_images';
  static const String cachedDocumentsTable = 'cached_documents';
  static const String cachedSnapshotsTable = 'cached_snapshots';
  static const String comicSearchRefreshQueueTable =
      'comic_search_refresh_queue';
  static const String novelSourceStateTable = 'novel_source_state';
  static const String novelEpisodeSyncStagingTable =
      'novel_episode_sync_staging';

  static Future<Database> open({String? databaseName}) {
    // Keep database initialization behind the Future boundary. This makes
    // provider construction safe when a platform database factory is not yet
    // installed; callers can handle the failed open during their async load.
    return Future<Database>.sync(() {
      final targetDbName = databaseName ?? dbName;
      return openDatabase(
        targetDbName,
        version: dbVersion,
        onConfigure: (db) async {
          // 多个阶段的清理逻辑都依赖 schema 上声明的级联关系，这里显式打开
          // SQLite 外键约束，避免“表上写了 ON DELETE CASCADE，但运行时不生效”。
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _upgradeSchema(db, oldVersion, newVersion);
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          await _rebuildLatestSchema(db);
        },
      );
    });
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 27) {
      await _rebuildLatestSchema(db);
      return;
    }

    // Sqflite invokes onUpgrade once with the installed and target versions.
    // Apply every intervening migration so skipping an app release stays safe.
    if (oldVersion < 28 && newVersion >= 28) {
      await _upgradeFrom27To28(db);
    }
    if (oldVersion < 29 && newVersion >= 29) {
      await _upgradeFrom28To29(db);
    }
    if (oldVersion < 30 && newVersion >= 30) {
      await _upgradeFrom29To30(db);
    }
    if (oldVersion < 31 && newVersion >= 31) {
      await _upgradeFrom30To31(db);
    }
    if (oldVersion < 32 && newVersion >= 32) {
      await _upgradeFrom31To32(db);
    }
    if (oldVersion < 33 && newVersion >= 33) {
      await _upgradeFrom32To33(db);
    }
    if (oldVersion < 34 && newVersion >= 34) {
      await _upgradeFrom33To34(db);
    }
  }

  static Future<void> _upgradeFrom27To28(Database db) async {
    await db.execute(
      'ALTER TABLE $comicsTable ADD COLUMN custom_catalog_url TEXT',
    );
  }

  static Future<void> _upgradeFrom28To29(Database db) async {
    await _createNovelHydrationTables(db);
    await _backfillLegacyNovelSourceState(db);
  }

  static Future<void> _upgradeFrom29To30(Database db) async {
    await _addColumnIfMissing(
      db,
      table: worksTable,
      column: 'custom_title',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: worksTable,
      column: 'custom_cover_focus_x',
      definition: 'REAL',
    );
    await _addColumnIfMissing(
      db,
      table: worksTable,
      column: 'custom_cover_focus_y',
      definition: 'REAL',
    );
  }

  static Future<void> _upgradeFrom30To31(Database db) async {
    await _addColumnIfMissing(
      db,
      table: worksTable,
      column: 'cover_hidden',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _upgradeFrom31To32(Database db) async {
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
    await _createReadingProgressIndex(db);
  }

  static Future<void> _upgradeFrom32To33(Database db) async {
    await _addColumnIfMissing(
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
    await _createFavoriteDetailStateIndex(db);
  }

  static Future<void> _upgradeFrom33To34(Database db) async {
    await _addColumnIfMissing(
      db,
      table: novelReadingProgressTable,
      column: 'pagination_key',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      db,
      table: novelReadingProgressTable,
      column: 'anchor_text_offset',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) {
      return;
    }
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<void> _createTables(Database db) async {
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
        source_tid TEXT NOT NULL,
        source_url TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        publish_time_text TEXT,
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

    await _createSettingsTable(db);
    await _seedDefaultSettings(db);
    await _createReadingProgressTable(db);
    await _createNovelTables(db);
    await _createNovelHydrationTables(db);
    await _createNovelReadingProgressTable(db);
    await _createReaderBookmarksTable(db);
    await _createNovelShelfTables(db);
    await _createLibraryStateTables(db);
    await _createPhase7PerformanceIndexes(db);
    await _createFavoriteTables(db);
    await _createImageCacheTables(db);
    await _createDocumentCacheTables(db);
    await _createSnapshotCacheTables(db);
    await _createComicSearchRefreshQueueTable(db);
  }

  static Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $settingsTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _seedDefaultSettings(Database db) async {
    await db.insert(settingsTable, <String, Object?>{
      'key': 'grid_column_count',
      'value': '3',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _createReadingProgressTable(Database db) async {
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
    await _createReadingProgressIndex(db);
  }

  static Future<void> _createReadingProgressIndex(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reading_progress_comic_updated '
      'ON $readingProgressTable(comic_id, updated_at DESC)',
    );
  }

  /// Phase 0: 为小说模块预留统一内容表与阅读偏好表。
  ///
  /// 这一批表暂不与现有漫画流程耦合，先完成数据库地基与索引建设，
  /// 便于后续按阶段接入仓储与页面逻辑。
  static Future<void> _createNovelTables(Database db) async {
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

  static Future<void> _createNovelReadingProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $novelReadingProgressTable (
        novel_id TEXT PRIMARY KEY,
        episode_id TEXT NOT NULL,
        scroll_offset REAL NOT NULL,
        flow_mode TEXT,
        page_index INTEGER,
        anchor_node_id TEXT,
        anchor_text_offset INTEGER NOT NULL DEFAULT 0,
        pagination_key TEXT,
        progress_percent REAL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createNovelHydrationTables(Database db) async {
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

  static Future<void> _backfillLegacyNovelSourceState(Database db) async {
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

  static Future<void> _createReaderBookmarksTable(Database db) async {
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
  static Future<void> _createNovelShelfTables(Database db) async {
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

  /// Phase 1: 统一状态表（未读/下载/书签/标签/显示配置）。
  static Future<void> _createLibraryStateTables(Database db) async {
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
  static Future<void> _createPhase7PerformanceIndexes(Database db) async {
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

  /// Phase 03：收藏线程缓存与收藏页自定义分类。
  ///
  /// 收藏是漫画/小说同步入口，但数据表保持独立，避免收藏页状态和
  /// 漫画/小说书架分类互相污染。
  static Future<void> _createFavoriteTables(Database db) async {
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
    await _createFavoriteDetailStateIndex(db);
  }

  static Future<void> _createFavoriteDetailStateIndex(Database db) {
    return db.execute(
      'CREATE INDEX IF NOT EXISTS idx_favorite_threads_active_detail_state_order ON '
      '$favoriteThreadsTable(removed_at, detail_state, remote_order)',
    );
  }

  /// Phase 04：统一图片缓存表。
  ///
  /// 开发阶段不维护逐版本图片缓存迁移；最新版 schema 已直接包含
  /// `episode_images` 与作品封面的本地路径字段，这里只补独立缓存表
  /// 和与最新版读取路径有关的索引。
  static Future<void> _createImageCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cachedImagesTable (
        cache_key TEXT PRIMARY KEY,
        owner_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        episode_id TEXT,
        image_index INTEGER,
        role TEXT NOT NULL,
        last_source_url TEXT,
        local_path TEXT,
        bytes INTEGER NOT NULL DEFAULT 0,
        mime_type TEXT,
        width INTEGER,
        height INTEGER,
        protected INTEGER NOT NULL DEFAULT 0,
        retention_class TEXT NOT NULL DEFAULT 'ephemeral',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_images_owner ON '
      '$cachedImagesTable(owner_type, owner_id, role)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_images_prune ON '
      '$cachedImagesTable(protected, retention_class, last_accessed_at, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episode_images_stable_key ON '
      '$episodeImagesTable(stable_cache_key)',
    );
  }

  /// 原生模式 Phase 3：HTML 文档缓存。
  ///
  /// 只保存 GET 页面 HTML；评分、点评、投票、回复等提交响应不进入这里。
  static Future<void> _createDocumentCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cachedDocumentsTable (
        cache_key TEXT PRIMARY KEY,
        namespace TEXT NOT NULL,
        owner_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        source_url TEXT NOT NULL,
        request_profile TEXT NOT NULL DEFAULT 'logged_in',
        body TEXT NOT NULL,
        content_type TEXT,
        status_code INTEGER,
        body_bytes INTEGER NOT NULL DEFAULT 0,
        fetched_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_documents_owner ON '
      '$cachedDocumentsTable(owner_type, owner_id, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_documents_namespace ON '
      '$cachedDocumentsTable(namespace, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_documents_access ON '
      '$cachedDocumentsTable(last_accessed_at, updated_at)',
    );
  }

  /// 原生模式 Phase 4：解析快照缓存。
  ///
  /// `parser_version` 与 `codec_version` 用于让 parser/model 结构变更后
  /// 自动忽略旧快照，避免 UI 读取过期结构。
  static Future<void> _createSnapshotCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cachedSnapshotsTable (
        cache_key TEXT PRIMARY KEY,
        owner_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        snapshot_type TEXT NOT NULL,
        codec_version INTEGER NOT NULL,
        parser_version INTEGER NOT NULL,
        source_document_key TEXT,
        payload_json TEXT NOT NULL,
        payload_bytes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_accessed_at INTEGER,
        stale_at INTEGER,
        expires_at INTEGER,
        FOREIGN KEY (source_document_key) REFERENCES $cachedDocumentsTable(cache_key) ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_snapshots_owner ON '
      '$cachedSnapshotsTable(owner_type, owner_id, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_snapshots_type_version ON '
      '$cachedSnapshotsTable(snapshot_type, codec_version, parser_version)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cached_snapshots_access ON '
      '$cachedSnapshotsTable(last_accessed_at, updated_at)',
    );
  }

  /// 收藏自动刷新阶段 3：漫画搜索等待队列。
  ///
  /// 队列表只保存“需要走搜索/当前帖回退”的后台刷新任务；catalog-only
  /// 成功的作品不进入这里，避免把立即刷新和搜索冷却调度混在一起。
  static Future<void> _createComicSearchRefreshQueueTable(Database db) async {
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

  /// 开发期数据库策略：不维护复杂的历史兼容迁移。
  ///
  /// 当前 App 仍处于开发阶段，旧本地库可以安全丢弃。升级/降级时先删除
  /// 本模块管理的表，再按最新版 schema 重新创建，避免迁移链为了兼容
  /// 半成品历史表结构不断膨胀。
  static Future<void> _rebuildLatestSchema(Database db) async {
    for (final tableName in _managedTablesInDropOrder) {
      await db.execute('DROP TABLE IF EXISTS $tableName');
    }
    await _createTables(db);
  }

  static const List<String> _managedTablesInDropOrder = <String>[
    novelEpisodeSyncStagingTable,
    novelSourceStateTable,
    comicSearchRefreshQueueTable,
    cachedSnapshotsTable,
    cachedDocumentsTable,
    favoriteThreadCategoryTable,
    favoriteCategoriesTable,
    favoriteThreadsTable,
    favoriteSyncStateTable,
    libraryWorkTagsTable,
    libraryTagsTable,
    libraryEpisodeStateTable,
    libraryWorkStateTable,
    libraryDisplaySettingsTable,
    readerBookmarksTable,
    novelEpisodeContentTable,
    workEpisodesTable,
    novelShelfItemsTable,
    novelCategoriesTable,
    novelReadingProgressTable,
    readerPreferencesTable,
    worksTable,
    cachedImagesTable,
    readingProgressTable,
    shelfItemsTable,
    categoriesTable,
    episodeImagesTable,
    episodesTable,
    comicsTable,
    settingsTable,
  ];
}
