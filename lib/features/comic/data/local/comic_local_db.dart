import 'package:sqflite/sqflite.dart';

/// 漫画本地数据库定义与建表逻辑。
class ComicLocalDb {
  ComicLocalDb._();

  static const String dbName = 'comic_shelf.db';
  static const int dbVersion = 13;

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

  static Future<Database> open({String? databaseName}) {
    final targetDbName = databaseName ?? dbName;
    return openDatabase(
      targetDbName,
      version: dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _rebuildLatestSchema(db);
      },
      onDowngrade: (db, oldVersion, newVersion) async {
        await _rebuildLatestSchema(db);
      },
    );
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
        author TEXT,
        cover_image_url TEXT,
        custom_cover_image_url TEXT,
        cover_local_path TEXT,
        custom_cover_local_path TEXT,
        translation_group TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_read_episode_id TEXT
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
        bytes INTEGER NOT NULL DEFAULT 0,
        mime_type TEXT,
        last_accessed_at INTEGER,
        protected INTEGER NOT NULL DEFAULT 0,
        cache_local_path TEXT,
        cache_status TEXT NOT NULL DEFAULT 'none',
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
    await _createNovelReadingProgressTable(db);
    await _createNovelShelfTables(db);
    await _createLibraryStateTables(db);
    await _createPhase7PerformanceIndexes(db);
    await _createFavoriteTables(db);
    await _createImageCacheTables(db);
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
    await db.insert(
      settingsTable,
      <String, Object?>{
        'key': 'grid_column_count',
        'value': '3',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _createReadingProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $readingProgressTable (
        comic_id TEXT PRIMARY KEY,
        episode_id TEXT NOT NULL,
        image_index INTEGER NOT NULL,
        scroll_offset REAL NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (comic_id) REFERENCES $comicsTable(comic_id) ON DELETE CASCADE
      )
    ''');
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
        author TEXT,
        cover_image_url TEXT,
        cover_local_path TEXT,
        custom_cover_local_path TEXT,
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
        font_family TEXT
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
        updated_at INTEGER NOT NULL
      )
    ''');
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

    await db.insert(
      novelCategoriesTable,
      <String, Object?>{
        'category_id': 'default',
        'name': '默认',
        'sort_order': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

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
        protected INTEGER NOT NULL DEFAULT 0,
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
      '$cachedImagesTable(protected, last_accessed_at, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episode_images_stable_key ON '
      '$episodeImagesTable(stable_cache_key)',
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
    favoriteThreadCategoryTable,
    favoriteCategoriesTable,
    favoriteThreadsTable,
    favoriteSyncStateTable,
    libraryWorkTagsTable,
    libraryTagsTable,
    libraryEpisodeStateTable,
    libraryWorkStateTable,
    libraryDisplaySettingsTable,
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
