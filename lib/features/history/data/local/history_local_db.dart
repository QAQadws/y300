import 'package:sqflite/sqflite.dart';

class HistoryLocalDb {
  HistoryLocalDb._();

  static const String dbName = 'history_records.db';
  static const int dbVersion = 1;
  static const String entriesTable = 'history_entries';
  static const String recentIndex = 'idx_history_entries_recent';

  static Future<Database> open({String? databaseName}) {
    return openDatabase(
      databaseName ?? dbName,
      version: dbVersion,
      onCreate: (db, version) => _createSchema(db),
      onDowngrade: (db, oldVersion, newVersion) {
        throw StateError(
          'History database downgrade is unsupported: $oldVersion -> $newVersion',
        );
      },
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $entriesTable (
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        title TEXT NOT NULL,
        context_label TEXT NOT NULL,
        thumbnail_local_path TEXT,
        thumbnail_remote_url TEXT,
        thumbnail_focus_x REAL,
        thumbnail_focus_y REAL,
        source_tid TEXT,
        canonical_url TEXT,
        last_page INTEGER,
        forum_name TEXT,
        last_surface TEXT NOT NULL,
        first_visited_at INTEGER NOT NULL,
        last_visited_at INTEGER NOT NULL,
        visit_count INTEGER NOT NULL DEFAULT 1 CHECK (visit_count > 0),
        PRIMARY KEY (target_type, target_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX $recentIndex
      ON $entriesTable(
        last_visited_at DESC,
        target_type ASC,
        target_id ASC
      )
    ''');
  }
}
