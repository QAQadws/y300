import 'package:sqflite/sqflite.dart';

final class BlogDraftDatabase {
  static const name = 'blog_drafts.db';
  static const table = 'blog_drafts';

  static Future<Database> open({String databaseName = name}) => openDatabase(
    databaseName,
    version: 1,
    onCreate: (db, _) => db.execute('''
      CREATE TABLE $table (
        account_id TEXT PRIMARY KEY,
        snapshot_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    '''),
  );
}
