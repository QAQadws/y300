import 'package:sqflite/sqflite.dart';

/// 漫画本地数据库定义与建表逻辑。
class ComicLocalDb {
  ComicLocalDb._();

  static const String dbName = 'comic_shelf.db';
  static const int dbVersion = 3;

  static const String comicsTable = 'comics';
  static const String episodesTable = 'episodes';
  static const String episodeImagesTable = 'episode_images';
  static const String categoriesTable = 'categories';
  static const String shelfItemsTable = 'shelf_items';
  static const String settingsTable = 'settings';
  static const String readingProgressTable = 'reading_progress';

  static Future<Database> open() {
    return openDatabase(
      dbName,
      version: dbVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSettingsTable(db);
          await _seedDefaultSettings(db);
        }
        if (oldVersion < 3) {
          await _createReadingProgressTable(db);
        }
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE $comicsTable (
        comic_id TEXT PRIMARY KEY,
        source_tid TEXT NOT NULL,
        source_fid TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        cover_image_url TEXT,
        custom_cover_image_url TEXT,
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
}
