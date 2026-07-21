import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('legacy DB upgrades all nullable pagination identity fields', () async {
    final temp = await Directory.systemTemp.createTemp(
      'y300-novel-phase4-migration-',
    );
    final dbPath = p.join(temp.path, 'phase4.db');
    addTearDown(() async {
      await deleteDatabase(dbPath);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    var db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 33,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.novelReadingProgressTable} (
              novel_id TEXT PRIMARY KEY,
              episode_id TEXT NOT NULL,
              scroll_offset REAL NOT NULL,
              flow_mode TEXT,
              page_index INTEGER,
              anchor_node_id TEXT,
              progress_percent REAL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.insert(ComicLocalDb.novelReadingProgressTable, {
            'novel_id': 'novel:legacy',
            'episode_id': 'episode:legacy',
            'scroll_offset': 10.0,
            'page_index': 4,
            'anchor_node_id': 'node-4',
            'progress_percent': 0.4,
            'updated_at': 1,
          });
        },
      ),
    );
    await db.close();

    db = await ComicLocalDb.open(databaseName: dbPath);
    addTearDown(db.close);
    expect(await db.getVersion(), ComicLocalDb.dbVersion);

    final columns = (await db.rawQuery(
      'PRAGMA table_info(${ComicLocalDb.novelReadingProgressTable})',
    )).map((row) => row['name']).toSet();
    expect(
      columns,
      containsAll(<String>{
        'anchor_text_offset',
        'pagination_key',
        'page_count',
      }),
    );
    final row = (await db.query(
      ComicLocalDb.novelReadingProgressTable,
      where: 'novel_id = ?',
      whereArgs: <Object?>['novel:legacy'],
      limit: 1,
    )).single;
    expect(row['page_index'], 4);
    expect(row['anchor_node_id'], 'node-4');
    expect(row['anchor_text_offset'], 0);
    expect(row['pagination_key'], isNull);
    expect(row['page_count'], isNull);
  });
}
