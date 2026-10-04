import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'v40 upgrade preserves cache payloads and adds v41 metadata defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'y300-cache-v41-',
      );
      final databasePath = p.join(directory.path, AppDatabase.dbName);
      Database? database;
      addTearDown(() async {
        await database?.close();
        await directory.delete(recursive: true);
      });

      var db = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 40,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE cached_images (
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
            await db.execute('''
            CREATE TABLE cached_documents (
              cache_key TEXT PRIMARY KEY,
              body TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE cached_snapshots (
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
              FOREIGN KEY (source_document_key) REFERENCES cached_documents(cache_key) ON DELETE SET NULL
            )
          ''');
          },
        ),
      );
      database = db;
      await db.insert('cached_images', <String, Object?>{
        'cache_key': 'image',
        'owner_type': 'comic',
        'owner_id': 'comic:100',
        'role': 'episode',
        'last_source_url': 'https://img.test/original.jpg',
        'local_path': '/existing/original.jpg',
        'bytes': 123,
        'protected': 1,
        'retention_class': 'longTerm',
        'created_at': 1,
        'updated_at': 2,
        'last_accessed_at': 3,
      });
      await db.insert('cached_documents', {
        'cache_key': 'document',
        'body': '<p>body</p>',
      });
      await db.insert('cached_snapshots', <String, Object?>{
        'cache_key': 'snapshot',
        'owner_type': 'novel',
        'owner_id': 'novel:200',
        'snapshot_type': 'thread',
        'codec_version': 2,
        'parser_version': 3,
        'source_document_key': 'document',
        'payload_json': '{"title":"existing"}',
        'payload_bytes': 20,
        'created_at': 1,
        'updated_at': 2,
        'last_accessed_at': 3,
        'stale_at': 4,
        'expires_at': 5,
      });
      final oldImage = (await db.query('cached_images')).single;
      final oldSnapshot = (await db.query('cached_snapshots')).single;
      await db.close();

      db = await AppDatabase.open(databaseName: databasePath);
      database = db;
      expect(await db.getVersion(), 41);
      expect(
        (await db.query(AppDatabase.cachedImagesTable)).single,
        <String, Object?>{...oldImage, 'etag': null, 'content_hash': null},
      );
      expect(
        (await db.query(AppDatabase.cachedSnapshotsTable)).single,
        <String, Object?>{...oldSnapshot, 'retain_long_term': 0},
      );
      expect(
        (await db.query(AppDatabase.cachedDocumentsTable)).single['body'],
        '<p>body</p>',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      await db.update(AppDatabase.cachedImagesTable, {
        'etag': 'existing-etag',
        'content_hash': 'existing-hash',
      });
      await db.update(AppDatabase.cachedSnapshotsTable, {
        'retain_long_term': 1,
      });
      await db.close();
      db = await AppDatabase.open(databaseName: databasePath);
      database = db;
      expect(
        (await db.query(AppDatabase.cachedImagesTable)).single,
        <String, Object?>{
          ...oldImage,
          'etag': 'existing-etag',
          'content_hash': 'existing-hash',
        },
      );
      expect(
        (await db.query(AppDatabase.cachedSnapshotsTable)).single,
        <String, Object?>{...oldSnapshot, 'retain_long_term': 1},
      );
    },
  );
}
