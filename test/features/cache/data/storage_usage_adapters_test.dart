import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/services/document_cache_service.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/parsed_snapshot_cache_service.dart';
import 'package:y300/features/cache/data/services/storage_usage_adapters.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'ImageCacheStorageAccountingAdapter groups image cache by role',
    () async {
      const dbName = 'storage_usage_image_cache_test.db';
      await deleteDatabase(dbName);
      final repository = LocalImageCacheRepository(
        ComicLocalDb.open(databaseName: dbName),
      );
      final now = DateTime(2026, 1, 1);

      await repository.upsert(
        CachedImageRecord(
          cacheKey: 'cover/comic/1',
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: '1',
          role: ImageCacheRole.cover.dbValue,
          bytes: 100,
          protected: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.upsert(
        CachedImageRecord(
          cacheKey: 'thread/1/0',
          ownerType: 'thread',
          ownerId: '1',
          role: 'thread_inline',
          retentionClass: ImageRetentionClass.recentReader,
          bytes: 40,
          protected: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.upsert(
        CachedImageRecord(
          cacheKey: 'smiley/1',
          ownerType: ImageCacheOwnerType.sticker.dbValue,
          ownerId: 'smiley',
          role: ImageCacheRole.remoteSmiley.dbValue,
          retentionClass: ImageRetentionClass.sticky,
          bytes: 20,
          protected: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final section = await ImageCacheStorageAccountingAdapter(
        repository: repository,
      ).calculateUsage();

      expect(section.bucket, StorageBucket.imageCache);
      expect(section.bytes, 160);
      expect(section.clearable, isTrue);
      expect(
        section.slices.map((slice) => slice.label),
        containsAll(<String>['封面（受保护）', '帖子图片（最近阅读）', '表情图片（低淘汰）']),
      );
      expect(section.categories.map((category) => category.label), <String>[
        '可清缓存',
        '长期缓存',
        '受保护/下载内容',
      ]);
      expect(section.categories.map((category) => category.bytes), <int>[
        40,
        20,
        100,
      ]);

      await deleteDatabase(dbName);
    },
  );

  test(
    'PageCacheStorageAccountingAdapter reports document cache usage',
    () async {
      const dbName = 'storage_usage_page_cache_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final documentCache = LocalDocumentCacheService(Future.value(db));
      final snapshotCache = LocalParsedSnapshotCacheService(Future.value(db));
      final now = DateTime(2026, 1, 1);
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });

      await documentCache.put(
        CachedDocument(
          cacheKey: 'document|thread|tid=1&page=1',
          ownerType: CacheOwnerType.thread,
          ownerId: 'tid=1&page=1',
          sourceUrl:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
          body: 'abc',
          fetchedAt: now,
          updatedAt: now,
        ),
      );
      await snapshotCache.put(
        const SnapshotCacheDescriptor(
          cacheKey: 'snapshot|thread|tid=1&page=1',
          ownerType: CacheOwnerType.thread,
          ownerId: 'tid=1&page=1',
          snapshotType: 'thread.detail',
        ),
        'hello',
        const _StringSnapshotCodec(),
        policy: const SnapshotCachePolicy(
          freshFor: Duration(minutes: 5),
          keepStaleFor: Duration(days: 1),
        ),
      );

      final section = await PageCacheStorageAccountingAdapter(
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
      ).calculateUsage();

      expect(section.bucket, StorageBucket.pageCache);
      expect(section.bytes, greaterThan(3));
      expect(section.clearable, isTrue);
      expect(
        section.slices.map((slice) => slice.label),
        containsAll(<String>['帖子详情 HTML（1）', '帖子详情快照（1）']),
      );
    },
  );

  test(
    'ComposerDraftStorageAccountingAdapter counts draft preference bytes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reply_draft.thread:33:100': '百合 draft',
        'unrelated': 'ignored',
      });
      final prefs = await SharedPreferences.getInstance();

      final section = await ComposerDraftStorageAccountingAdapter(
        sharedPreferences: prefs,
      ).calculateUsage();

      expect(section.bucket, StorageBucket.composerDraft);
      expect(section.clearable, isTrue);
      expect(section.bytes, greaterThan('百合 draft'.length));
      expect(section.slices.single.label, '发帖/回复草稿（1）');
    },
  );

  test(
    'DownloadStorageAccountingAdapter recursively counts download files',
    () async {
      final temp = await io.Directory.systemTemp.createTemp(
        'storage_usage_download_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final comics = io.Directory('${temp.path}/comics');
      final novels = io.Directory('${temp.path}/novels');
      await comics.create(recursive: true);
      await novels.create(recursive: true);
      await io.File('${comics.path}/001.cbz').writeAsBytes(<int>[1, 2, 3]);
      await io.File('${novels.path}/chapter.txt').writeAsBytes(<int>[4, 5]);
      await io.File('${temp.path}/favorites.json').writeAsBytes(<int>[6]);

      final section = await DownloadStorageAccountingAdapter(
        storageService: _FakeDownloadStorageService(
          DownloadStorageRoot(
            path: temp.path,
            comicsPath: comics.path,
            novelsPath: novels.path,
            favoritesJsonPath: '${temp.path}/favorites.json',
          ),
        ),
      ).calculateUsage();

      expect(section.bucket, StorageBucket.download);
      expect(section.bytes, 6);
      expect(section.clearable, isFalse);
      expect(
        section.slices.map((slice) => slice.id),
        contains('download:comics'),
      );
      expect(
        section.slices.map((slice) => slice.id),
        contains('download:novels'),
      );
    },
  );

  test(
    'LibraryMetadataStorageAccountingAdapter reports sqlite and table counts',
    () async {
      const dbName = 'storage_usage_library_metadata_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      final dbFile = io.File('${io.Directory.systemTemp.path}/$dbName-file.db');
      await dbFile.writeAsBytes(List<int>.filled(11, 7));
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
      });
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await db.insert(ComicLocalDb.comicsTable, <String, Object?>{
        'comic_id': 'comic-1',
        'source_tid': '100',
        'source_fid': '33',
        'title': 'title',
        'created_at': now,
        'updated_at': now,
      });

      final section = await LibraryMetadataStorageAccountingAdapter(
        databaseFuture: Future<Database>.value(db),
        databasePathFuture: Future<String>.value(dbFile.path),
      ).calculateUsage();

      expect(section.bucket, StorageBucket.libraryMetadata);
      expect(section.bytes, 11);
      expect(section.clearable, isFalse);
      expect(section.slices.map((slice) => slice.label), contains('本地数据库'));
      expect(section.slices.map((slice) => slice.label), contains('漫画作品：1'));
    },
  );

  test(
    'HistoryStorageAccountingAdapter reports protected bytes and count',
    () async {
      const dbName = 'storage_usage_history_test.db';
      await deleteDatabase(dbName);
      final db = await HistoryLocalDb.open(databaseName: dbName);
      final dbFile = io.File('${io.Directory.systemTemp.path}/$dbName-file.db');
      await dbFile.writeAsBytes(List<int>.filled(17, 7));
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
      });
      final at = DateTime.utc(2026, 7, 16).millisecondsSinceEpoch;
      await db.insert(HistoryLocalDb.entriesTable, <String, Object?>{
        'target_type': 'thread',
        'target_id': '100',
        'title': '帖子',
        'context_label': '详情',
        'last_surface': 'threadNative',
        'first_visited_at': at,
        'last_visited_at': at,
        'visit_count': 1,
      });

      final section = await HistoryStorageAccountingAdapter(
        databaseFuture: Future<Database>.value(db),
        databasePathFuture: Future<String>.value(dbFile.path),
      ).calculateUsage();

      expect(section.bucket, StorageBucket.history);
      expect(section.bytes, 17);
      expect(section.clearable, isFalse);
      expect(section.slices.map((slice) => slice.label), <String>[
        '记录数据库',
        '浏览记录：1',
      ]);
      expect(section.slices.every((slice) => slice.protected), isTrue);
    },
  );
}

class _StringSnapshotCodec implements SnapshotCodec<String> {
  const _StringSnapshotCodec();

  @override
  String get snapshotType => 'thread.detail';

  @override
  int get codecVersion => 1;

  @override
  int get parserVersion => 1;

  @override
  Object? encode(String value) => <String, Object?>{'value': value};

  @override
  String decode(Object? json) =>
      (json as Map<String, dynamic>)['value'] as String;
}

class _FakeDownloadStorageService implements DownloadStorageService {
  const _FakeDownloadStorageService(this.root);

  final DownloadStorageRoot root;

  @override
  Future<DownloadStorageRoot> prepareRoot() async => root;

  @override
  Future<io.Directory> prepareComicDirectory({
    required String workId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<io.Directory> prepareNovelDirectory({
    required String novelId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> deleteComicDownloads({required String workId}) async => false;

  @override
  Future<bool> deleteNovelDownloads({required String novelId}) async => false;

  @override
  String safeFileName(String value, {String fallback = 'untitled'}) => value;

  @override
  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  }) {
    return title;
  }

  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) {
    throw UnimplementedError();
  }

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) {
    throw UnimplementedError();
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  }) async {
    return null;
  }

  @override
  Future<DownloadedNovelChapter?> findDownloadedNovelChapter({
    required String novelId,
    required String title,
    required String episodeId,
  }) async {
    return null;
  }
}
