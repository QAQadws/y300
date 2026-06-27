import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/image_cache_repository.dart';
import 'package:y300/features/cache/data/storage_usage_adapters.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
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
          bytes: 40,
          protected: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final section = await ImageCacheStorageAccountingAdapter(
        repository: repository,
      ).calculateUsage();

      expect(section.bucket, StorageBucket.imageCache);
      expect(section.bytes, 140);
      expect(section.clearable, isTrue);
      expect(
        section.slices.map((slice) => slice.label),
        containsAll(<String>['封面（受保护）', '帖子图片']),
      );

      await deleteDatabase(dbName);
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
