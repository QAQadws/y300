import 'package:sqflite/sqflite.dart';

class ComposerDraftLocalDb {
  ComposerDraftLocalDb._();

  static const String dbName = 'composer_drafts.db';
  static const int dbVersion = 1;
  static const String draftsTable = 'composer_drafts';
  static const String threadIndex = 'idx_composer_drafts_thread';
  static const String recentIndex = 'idx_composer_drafts_recent';

  static Future<Database> open({String? databaseName}) {
    return openDatabase(
      databaseName ?? dbName,
      version: dbVersion,
      onCreate: (db, version) => _createSchema(db),
      onDowngrade: (db, oldVersion, newVersion) {
        throw StateError(
          'Composer draft database downgrade is unsupported: '
          '$oldVersion -> $newVersion',
        );
      },
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $draftsTable (
        storage_key TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        fid TEXT NOT NULL,
        tid TEXT,
        snapshot_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX $threadIndex
      ON $draftsTable(fid, tid, kind, updated_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX $recentIndex
      ON $draftsTable(updated_at DESC, storage_key ASC)
    ''');
  }
}
