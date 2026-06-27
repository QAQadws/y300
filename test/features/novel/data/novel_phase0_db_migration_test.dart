import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'ComicLocalDb phase0 migration creates novel infrastructure tables',
    () async {
      const dbName = 'comic_shelf_test_phase0.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);

      final tableRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = tableRows.map((row) => row['name'] as String).toSet();

      expect(tableNames.contains(ComicLocalDb.worksTable), isTrue);
      expect(tableNames.contains(ComicLocalDb.workEpisodesTable), isTrue);
      expect(
        tableNames.contains(ComicLocalDb.novelEpisodeContentTable),
        isTrue,
      );
      expect(tableNames.contains(ComicLocalDb.readerPreferencesTable), isTrue);
      expect(
        tableNames.contains(ComicLocalDb.novelReadingProgressTable),
        isTrue,
      );
      expect(tableNames.contains(ComicLocalDb.readerBookmarksTable), isTrue);
      expect(ComicLocalDb.dbVersion, 22);

      final indexRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final indexNames = indexRows.map((row) => row['name'] as String).toSet();

      expect(indexNames.contains('idx_work_type_updated'), isTrue);
      expect(indexNames.contains('idx_episode_work_order'), isTrue);
      expect(indexNames.contains('idx_episode_tid_pid'), isTrue);
      expect(indexNames.contains('idx_reader_bookmarks_novel_episode'), isTrue);

      final progressColumns = await db.rawQuery(
        'PRAGMA table_info(${ComicLocalDb.novelReadingProgressTable})',
      );
      final progressColumnNames = progressColumns
          .map((row) => row['name'] as String)
          .toSet();
      expect(progressColumnNames.contains('flow_mode'), isTrue);
      expect(progressColumnNames.contains('page_index'), isTrue);
      expect(progressColumnNames.contains('anchor_node_id'), isTrue);
      expect(progressColumnNames.contains('progress_percent'), isTrue);

      await db.close();
      await deleteDatabase(dbName);
    },
  );
}
