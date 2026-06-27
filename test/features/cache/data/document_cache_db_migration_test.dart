import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'ComicLocalDb latest schema includes document and snapshot cache tables',
    () async {
      const dbName = 'document_cache_db_migration_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((row) => row['name']).toSet();
      expect(tableNames.contains(ComicLocalDb.cachedDocumentsTable), isTrue);

      final columns = await db.rawQuery(
        'PRAGMA table_info(${ComicLocalDb.cachedDocumentsTable})',
      );
      final columnNames = columns.map((row) => row['name']).toSet();
      expect(columnNames.contains('cache_key'), isTrue);
      expect(columnNames.contains('owner_type'), isTrue);
      expect(columnNames.contains('owner_id'), isTrue);
      expect(columnNames.contains('request_profile'), isTrue);
      expect(columnNames.contains('body'), isTrue);
      expect(columnNames.contains('body_bytes'), isTrue);
      expect(columnNames.contains('last_accessed_at'), isTrue);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(indexNames.contains('idx_cached_documents_owner'), isTrue);
      expect(indexNames.contains('idx_cached_documents_namespace'), isTrue);
      expect(indexNames.contains('idx_cached_documents_access'), isTrue);

      expect(tableNames.contains(ComicLocalDb.cachedSnapshotsTable), isTrue);

      final snapshotColumns = await db.rawQuery(
        'PRAGMA table_info(${ComicLocalDb.cachedSnapshotsTable})',
      );
      final snapshotColumnNames = snapshotColumns
          .map((row) => row['name'])
          .toSet();
      expect(snapshotColumnNames.contains('cache_key'), isTrue);
      expect(snapshotColumnNames.contains('snapshot_type'), isTrue);
      expect(snapshotColumnNames.contains('codec_version'), isTrue);
      expect(snapshotColumnNames.contains('parser_version'), isTrue);
      expect(snapshotColumnNames.contains('source_document_key'), isTrue);
      expect(snapshotColumnNames.contains('payload_json'), isTrue);
      expect(snapshotColumnNames.contains('payload_bytes'), isTrue);
      expect(snapshotColumnNames.contains('expires_at'), isTrue);

      expect(indexNames.contains('idx_cached_snapshots_owner'), isTrue);
      expect(indexNames.contains('idx_cached_snapshots_type_version'), isTrue);
      expect(indexNames.contains('idx_cached_snapshots_access'), isTrue);
    },
  );
}
