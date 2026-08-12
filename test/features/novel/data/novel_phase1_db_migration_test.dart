import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

import '../test_support/novel_phase0_persistence_baseline.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'DB 28 to current preserves novel data and adds cover visibility state',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'y300-novel-phase1-migration-',
      );
      final dbPath = p.join(temp.path, 'phase1.db');
      addTearDown(() async {
        await deleteDatabase(dbPath);
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      var db = await ComicLocalDb.open(databaseName: dbPath);
      await prepareNovelPhase0DatabaseVersion28(db);
      await seedNovelPhase0PersistenceBaseline(db);
      await db.insert(ComicLocalDb.worksTable, <String, Object?>{
        'work_id': 'novel:55:metadata-only',
        'content_type': 'novel',
        'source_tid': 'metadata-only',
        'source_fid': '55',
        'title': '零章节旧小说',
        'author': '旧发布者',
        'updated_at': 1783900800000,
      });
      final before = await readNovelPhase0PersistenceBaseline(db);
      expect(await db.getVersion(), 28);
      await db.close();

      db = await ComicLocalDb.open(databaseName: dbPath);
      addTearDown(db.close);
      expect(await db.getVersion(), ComicLocalDb.dbVersion);
      final after = await readNovelPhase0PersistenceBaseline(db);

      // A legacy custom-cover path is an existing user asset. Migration gives
      // it the first revision so the new stable cover identity can address it.
      final expectedWork = Map<String, Object?>.from(before.work)
        ..['custom_cover_revision'] = 1;
      expect(after.work, expectedWork);
      expect(after.episode, before.episode);
      expect(after.content, before.content);
      expect(after.shelfItem, before.shelfItem);
      expect(after.workState, before.workState);
      expect(after.episodeState, before.episodeState);
      for (final entry in before.readingProgress.entries) {
        expect(after.readingProgress[entry.key], entry.value);
      }
      expect(after.readingProgress['anchor_text_offset'], 0);
      expect(after.readingProgress['pagination_key'], isNull);
      expect(after.bookmark, before.bookmark);

      final workColumns = (await db.rawQuery(
        'PRAGMA table_info(${ComicLocalDb.worksTable})',
      )).map((row) => row['name']).toSet();
      expect(
        workColumns,
        containsAll(<String>{
          'custom_title',
          'custom_cover_focus_x',
          'custom_cover_focus_y',
          'cover_hidden',
        }),
      );
      final migratedWork = (await db.query(
        ComicLocalDb.worksTable,
        where: 'work_id = ?',
        whereArgs: <Object?>[novelPhase0BaselineNovelId],
        limit: 1,
      )).single;
      expect(migratedWork['cover_hidden'], 0);

      final legacyState = await _sourceState(db, novelPhase0BaselineNovelId);
      expect(legacyState['publisher_id'], isNull);
      expect(legacyState['publisher_name'], 'INCSKY16');
      expect(legacyState['metadata_source_version'], isNull);
      expect(legacyState['source_catalog_json'], '[]');
      expect(legacyState['hydration_state'], 'legacyNeedsRebuild');
      expect(legacyState['last_completed_author_page'], 0);

      final metadataOnlyState = await _sourceState(
        db,
        'novel:55:metadata-only',
      );
      expect(metadataOnlyState['publisher_id'], isNull);
      expect(metadataOnlyState['publisher_name'], '旧发布者');
      expect(metadataOnlyState['hydration_state'], 'metadataOnly');

      final tableNames = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']).toSet();
      expect(tableNames, contains(ComicLocalDb.novelSourceStateTable));
      expect(tableNames, contains(ComicLocalDb.novelEpisodeSyncStagingTable));

      final indexNames = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      )).map((row) => row['name']).toSet();
      expect(indexNames, contains('idx_novel_episode_stage_run'));
    },
  );
}

Future<Map<String, Object?>> _sourceState(Database db, String novelId) async {
  final rows = await db.query(
    ComicLocalDb.novelSourceStateTable,
    where: 'novel_id = ?',
    whereArgs: <Object?>[novelId],
    limit: 1,
  );
  expect(rows, hasLength(1));
  return rows.single;
}
