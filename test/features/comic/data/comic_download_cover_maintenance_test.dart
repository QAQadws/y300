import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/services/comic_download_cover_maintenance.dart';
import 'package:y300/features/comic/data/services/comic_download_metadata_store.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/library_shared/data/services/library_cover_legacy_migrator.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';
import '../../storage/test_support/ready_storage_root_access_gate.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late io.Directory root;
  late Database db;
  late LocalLibraryCoverStore covers;
  late _Metadata metadata;
  late DefaultDownloadStorageService storage;
  late _Locations locations;
  late _Gate gate;
  late ComicDownloadCoverMaintenance maintenance;
  late io.Directory directory;
  late io.File legacy;
  const id = 'comic:fixture';
  const asset = LibraryCoverAssetRef(
    assetId: 'comic/comic:fixture/source',
    revision: 1,
    kind: LibraryCoverAssetKind.source,
    sourceUrl: 'https://example.test/cover',
  );
  final pixels = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp(
      'download-cover-maintenance-',
    );
    db = await ComicLocalDb.open(databaseName: p.join(root.path, 'fixture.db'));
    covers = LocalLibraryCoverStore(
      rootPath: Future.value(p.join(root.path, 'originals')),
      downloader: _NoNetwork(),
    );
    metadata = _Metadata();
    locations = _Locations(p.join(root.path, 'downloads'));
    storage = DefaultDownloadStorageService(locationRepository: locations);
    gate = _Gate();
    directory = await storage.prepareComicDirectory(
      workId: id,
      title: 'Fixture',
    );
    legacy = io.File(p.join(directory.path, 'cover.jpg'));
    await legacy.writeAsBytes(pixels);
    await io.File(
      p.join(directory.path, 'chapter.cbz'),
    ).writeAsBytes([1, 2, 3]);
    await metadata.write(directory, {
      'schemaVersion': 1,
      'contentType': 'comic',
      'workId': id,
      'coverFile': 'cover.jpg',
      'customCoverFile': null,
      'chapters': [
        {'episodeId': 'one', 'cbzFile': 'chapter.cbz'},
      ],
    });
    await db.insert(ComicLocalDb.comicsTable, {
      'comic_id': id,
      'source_tid': '1',
      'source_fid': '30',
      'title': 'Fixture',
      'cover_image_url': asset.sourceUrl,
      'cover_revision': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    maintenance = ComicDownloadCoverMaintenance(
      repository: _Repository(),
      storage: storage,
      accessGate: gate,
      migrator: LibraryCoverLegacyMigrator(
        database: Future.value(db),
        store: covers,
        legacyCacheRepository: LocalImageCacheRepository(Future.value(db)),
      ),
      covers: covers,
      metadata: metadata,
    );
  });
  tearDown(() async {
    maintenance.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> install() =>
      covers.installLocalFile(asset: asset, sourcePath: legacy.path);

  test(
    'verified duplicate is removed; chapters, archive and original survive',
    () async {
      await install();
      final first = maintenance.maintain(id);
      expect(identical(first, maintenance.maintain(id)), isTrue);
      await first;
      expect(await legacy.exists(), isFalse);
      expect(await (await covers.fileFor(asset)).readAsBytes(), pixels);
      final meta = (await metadata.read(directory))!;
      expect(meta['coverFile'], isNull);
      expect(meta['chapters'], hasLength(1));
      expect(
        await io.File(p.join(directory.path, 'chapter.cbz')).readAsBytes(),
        [1, 2, 3],
      );
      expect(gate.calls, 1);
    },
  );

  test(
    'per-work local adoption precedes deleting a referenced legacy copy',
    () async {
      await db.update(
        ComicLocalDb.comicsTable,
        {'cover_local_path': legacy.path},
        where: 'comic_id = ?',
        whereArgs: [id],
      );
      await maintenance.maintain(id);
      expect(await legacy.exists(), isFalse);
      final row = (await db.query(ComicLocalDb.comicsTable)).single;
      expect(row['cover_local_path'], isNull);
      final managed = LibraryCoverAssetRef(
        assetId: asset.assetId,
        revision: row['cover_revision'] as int,
        kind: asset.kind,
      );
      expect(await (await covers.fileFor(managed)).readAsBytes(), pixels);
    },
  );

  test(
    'missing or mismatching original preserves the duplicate without network',
    () async {
      await maintenance.maintain(id);
      expect(await legacy.exists(), isTrue);
      await install();
      final original = await covers.fileFor(asset);
      final changed = List<int>.from(pixels)..[pixels.length - 1] ^= 1;
      await original.writeAsBytes(changed);
      await maintenance.maintain(id);
      expect(await legacy.exists(), isTrue);
      expect(await original.readAsBytes(), changed);
      expect((await metadata.read(directory))!['coverFile'], 'cover.jpg');
    },
  );

  test(
    'other work references and unknown metadata references prevent deletion',
    () async {
      await install();
      await db.insert(ComicLocalDb.comicsTable, {
        'comic_id': 'other',
        'source_tid': '2',
        'source_fid': '30',
        'title': 'Other',
        'custom_cover_local_path': legacy.path,
        'created_at': 1,
        'updated_at': 1,
      });
      await maintenance.maintain(id);
      expect(await legacy.exists(), isTrue);
      await db.delete(
        ComicLocalDb.comicsTable,
        where: 'comic_id = ?',
        whereArgs: ['other'],
      );
      final meta = (await metadata.read(directory))!;
      await metadata.write(directory, {
        ...meta,
        'extra': {'image': 'cover.jpg'},
      });
      await maintenance.maintain(id);
      expect(await legacy.exists(), isTrue);
    },
  );

  test(
    'maintenance rereads metadata after a concurrent chapter commit',
    () async {
      await install();
      final entered = Completer<void>();
      final release = Completer<void>();
      final download = metadata.run(directory, () async {
        final meta = (await metadata.read(directory))!;
        entered.complete();
        await release.future;
        await metadata.write(directory, {
          ...meta,
          'chapters': [
            ...meta['chapters'] as List,
            {'episodeId': 'two', 'cbzFile': 'second.cbz'},
          ],
        });
      });
      await entered.future;
      final cleanup = maintenance.maintain(id);
      release.complete();
      await Future.wait([download, cleanup]);
      expect((await metadata.read(directory))!['chapters'], hasLength(2));
      expect(await legacy.exists(), isFalse);
    },
  );

  test(
    'root migration is resolved inside its lease, not from a stale path',
    () async {
      await install();
      final release = Completer<void>();
      gate.before = release.future;
      final cleanup = maintenance.maintain(id);
      final moved = p.join(root.path, 'moved');
      await io.Directory(locations.path).rename(moved);
      locations.path = moved;
      release.complete();
      await cleanup;
      directory = (await storage.findExistingComicDirectory(
        workId: id,
        title: 'Fixture',
      ))!;
      expect(
        await io.File(p.join(directory.path, 'cover.jpg')).exists(),
        isFalse,
      );
    },
  );

  test(
    'metadata publication failure preserves previous chapters and duplicate',
    () async {
      await install();
      final originalMeta = await io.File(
        p.join(directory.path, 'meta.json'),
      ).readAsString(encoding: utf8);
      metadata.fail = true;
      await maintenance.maintain(id);
      expect(await legacy.exists(), isTrue);
      expect(
        await io.File(
          p.join(directory.path, 'meta.json'),
        ).readAsString(encoding: utf8),
        originalMeta,
      );
      metadata.fail = false;
      await maintenance.maintain(id);
      expect(await legacy.exists(), isFalse);
    },
  );

  test('a file changed during maintenance is retained', () async {
    await install();
    metadata.beforeWrite = () async {
      await legacy.writeAsBytes([...pixels, 1]);
    };
    await maintenance.maintain(id);
    expect(await legacy.exists(), isTrue);
    expect(await legacy.length(), pixels.length + 1);
  });

  test('missing work directory is never recreated by maintenance', () async {
    await directory.delete(recursive: true);
    await maintenance.maintain(id);
    expect(await directory.exists(), isFalse);
  });

  test('corrupt metadata is retained along with the duplicate', () async {
    await install();
    final file = io.File(p.join(directory.path, 'meta.json'));
    await file.writeAsString('{incomplete', encoding: utf8);
    await maintenance.maintain(id);
    expect(await legacy.exists(), isTrue);
    expect(await file.readAsString(encoding: utf8), '{incomplete');
  });
}

class _Locations
    implements StorageLocationRepository, ExistingStorageRootLocator {
  _Locations(this.path);
  String path;
  @override
  Future<String> getDefaultStorageRoot() async => path;
  @override
  Future<String?> getCustomStorageRoot() async => path;
  @override
  Future<String?> getExistingStorageRoot() async =>
      await io.Directory(path).exists() ? path : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements ComicRepository {
  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async =>
      ComicDetail(
        comicId: comicId,
        sourceTid: '1',
        sourceFid: '30',
        title: 'Fixture',
        author: null,
        translationGroup: null,
        coverImageUrl: 'https://example.test/cover',
        updatedAt: DateTime(2026),
        episodeCount: 1,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoNetwork implements LibraryCoverDownloader {
  @override
  Future<void> download({required String url, required String targetPath}) =>
      throw StateError('Maintenance must never download');
}

class _Gate implements StorageRootAccessGate {
  int calls = 0;
  Future<void>? before;
  @override
  Future<T> runWithAccess<T>(Future<T> Function() operation) async {
    calls++;
    await before;
    return operation();
  }

  @override
  Future<StorageRootMigrationResult> ensureReady() async =>
      ReadyStorageRootAccessGate.result;
  @override
  Future<StorageRootMigrationResult> retry() => ensureReady();
}

class _Metadata extends ComicDownloadMetadataStore {
  bool fail = false;
  Future<void> Function()? beforeWrite;
  @override
  Future<void> write(io.Directory directory, Map<String, Object?> value) async {
    if (fail) throw const io.FileSystemException('Fixture publication failure');
    await beforeWrite?.call();
    await super.write(directory, value);
  }
}
