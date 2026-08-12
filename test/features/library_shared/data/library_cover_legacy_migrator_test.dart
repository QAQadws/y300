import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/services/library_cover_legacy_migrator.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const databaseName = 'library_cover_legacy_migrator_test.db';
  late io.Directory root;
  late Database db;
  late LocalLibraryCoverStore store;

  setUp(() async {
    await deleteDatabase(databaseName);
    db = await ComicLocalDb.open(databaseName: databaseName);
    root = await io.Directory.systemTemp.createTemp('y300-cover-migration-');
    store = LocalLibraryCoverStore(
      rootPath: Future<String>.value(root.path),
      downloader: _NoDownload(),
    );
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(databaseName);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'custom cover migration is idempotent and preserves legacy file',
    () async {
      final legacy = io.File('${root.path}/legacy-custom.png');
      await legacy.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      await db.insert(ComicLocalDb.comicsTable, <String, Object?>{
        'comic_id': 'comic:legacy',
        'source_tid': '1',
        'source_fid': '30',
        'title': 'Legacy',
        'custom_cover_local_path': legacy.path,
        'created_at': 1,
        'updated_at': 1,
      });
      final migrator = LibraryCoverLegacyMigrator(
        database: Future<Database>.value(db),
        store: store,
        legacyCacheRepository: LocalImageCacheRepository(Future.value(db)),
      );

      await migrator.migrateCustomAssets();
      await migrator.migrateCustomAssets();

      const asset = LibraryCoverAssetRef(
        assetId: 'comic/comic:legacy/custom',
        revision: 1,
        kind: LibraryCoverAssetKind.custom,
      );
      expect(await (await store.fileFor(asset)).exists(), isTrue);
      expect(await legacy.exists(), isTrue);
      final row = (await db.query(
        ComicLocalDb.comicsTable,
        where: 'comic_id = ?',
        whereArgs: const <Object>['comic:legacy'],
      )).single;
      expect(row['custom_cover_local_path'], isNull);
      expect(row['custom_cover_revision'], 1);
      final markers = await db.query(
        ComicLocalDb.libraryCoverMigrationsTable,
        where: 'asset_id = ?',
        whereArgs: const <Object>['comic/comic:legacy/custom'],
      );
      expect(markers, hasLength(1));
    },
  );
}

class _NoDownload implements LibraryCoverDownloader {
  @override
  Future<void> download({required String url, required String targetPath}) {
    throw StateError('network must not be used during this migration');
  }
}
