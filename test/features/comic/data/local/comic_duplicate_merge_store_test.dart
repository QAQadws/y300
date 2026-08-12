import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_duplicate_merge_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ComicDuplicateMergeStore', () {
    const databaseName = 'comic_duplicate_merge_store_test.db';

    late Future<Database> dbFuture;
    late LocalComicRepository repository;
    late ComicDuplicateMergeStore store;
    late io.Directory coverRoot;
    late LocalLibraryCoverStore libraryCoverStore;

    setUp(() async {
      await deleteDatabase(databaseName);
      dbFuture = ComicLocalDb.open(databaseName: databaseName);
      coverRoot = await io.Directory.systemTemp.createTemp(
        'y300-duplicate-cover-',
      );
      libraryCoverStore = LocalLibraryCoverStore(
        rootPath: Future<String>.value(coverRoot.path),
        downloader: const _NoCoverDownload(),
      );
      repository = LocalComicRepository(
        dbFuture,
        libraryCoverStore: libraryCoverStore,
      );
      store = ComicDuplicateMergeStore(
        dbFuture,
        coverStore: ComicCoverStore(dbFuture),
        libraryCoverStore: libraryCoverStore,
      );
    });

    tearDown(() async {
      if (await coverRoot.exists()) {
        await coverRoot.delete(recursive: true);
      }
    });

    test(
      'mergeDuplicateGroup chooses shortest title target and keeps shelf membership',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:1000',
          tid: '1000',
          fid: '30',
          title: 'Very Long Duplicate Comic Title',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-1001-1-1.html',
                rawText: '1',
                episodeTitle: 'chapter 1',
              ),
              ComicEpisodeLink(
                url: 'thread-1002-1-1.html',
                rawText: '2',
                episodeTitle: 'chapter 2',
              ),
            ],
            plainTextSummary: 'summary',
          ),
        );
        await repository.addToShelf(
          comicId: 'yamibo:2000',
          tid: '2000',
          fid: '30',
          title: 'Short',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-1002-1-1.html',
                rawText: '2',
                episodeTitle: 'chapter 2 full title',
              ),
              ComicEpisodeLink(
                url: 'thread-1003-1-1.html',
                rawText: '3',
                episodeTitle: 'chapter 3',
              ),
            ],
            plainTextSummary: 'summary',
          ),
        );

        final customCategoryId = await repository.createCategory(
          name: 'follow',
        );
        await repository.moveComicToCategory(
          comicId: 'yamibo:1000',
          fromCategoryId: 'default',
          toCategoryId: customCategoryId,
        );

        final result = await store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:1000', 'yamibo:2000'},
        );

        final detail = await repository.getComicDetail(
          comicId: result.targetComicId,
        );
        final episodes = await repository.getComicEpisodes(
          comicId: result.targetComicId,
          descending: false,
        );
        final defaultItems = await repository.getShelfItems(
          categoryId: 'default',
        );
        final customItems = await repository.getShelfItems(
          categoryId: customCategoryId,
        );

        expect(result.targetComicId, 'yamibo:2000');
        expect(result.targetTitle, 'Short');
        expect(detail?.title, 'Short');
        expect(episodes.map((episode) => episode.sourceTid).toList(), <String>[
          '1001',
          '1002',
          '1003',
        ]);
        expect(defaultItems.map((item) => item.comicId).toSet(), <String>{
          'yamibo:2000',
        });
        expect(customItems.map((item) => item.comicId).toSet(), <String>{
          'yamibo:2000',
        });
      },
    );

    test(
      'merge reowns a source cover file and removes source assets',
      () async {
        await _seedDuplicatePair(repository);
        final db = await dbFuture;
        await db.update(
          ComicLocalDb.comicsTable,
          <String, Object?>{
            'cover_image_url': 'https://img.test/source.jpg',
            'metadata_updated_at': 20,
          },
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:source'],
        );
        const sourceAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:source/source',
          revision: 1,
          kind: LibraryCoverAssetKind.source,
        );
        final picked = io.File('${coverRoot.path}/picked-source.jpg');
        await picked.writeAsBytes(<int>[0xff, 0xd8, 1, 2, 0xff, 0xd9]);
        await libraryCoverStore.installLocalFile(
          asset: sourceAsset,
          sourcePath: picked.path,
        );

        final result = await store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:source', 'yamibo:target'},
        );

        expect(result.targetComicId, 'yamibo:target');
        const targetAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:target/source',
          revision: 1,
          kind: LibraryCoverAssetKind.source,
        );
        expect(
          await (await libraryCoverStore.fileFor(targetAsset)).exists(),
          isTrue,
        );
        expect(
          await (await libraryCoverStore.fileFor(sourceAsset)).exists(),
          isFalse,
        );
        final detail = await repository.getComicDetail(
          comicId: 'yamibo:target',
        );
        expect(detail?.coverRevision, 1);
        expect(detail?.coverImageUrl, 'https://img.test/source.jpg');
        expect(
          await db.query(ComicLocalDb.comicCoverMergeOperationsTable),
          isEmpty,
        );
      },
    );

    test('valid target cover wins and keeps its complete identity', () async {
      await _seedDuplicatePair(repository);
      final db = await dbFuture;
      await db.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'cover_image_url': 'https://img.test/target.jpg',
          'metadata_updated_at': 10,
        },
        where: 'comic_id = ?',
        whereArgs: const <Object>['yamibo:target'],
      );
      await db.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'cover_image_url': 'https://img.test/newer-source.jpg',
          'metadata_updated_at': 99,
        },
        where: 'comic_id = ?',
        whereArgs: const <Object>['yamibo:source'],
      );
      await db.update(
        ComicLocalDb.comicsTable,
        const <String, Object?>{'cover_revision': 3},
        where: 'comic_id = ?',
        whereArgs: const <Object>['yamibo:target'],
      );
      const targetAsset = LibraryCoverAssetRef(
        assetId: 'comic/yamibo:target/source',
        revision: 3,
        kind: LibraryCoverAssetKind.source,
      );
      const oldTargetAsset = LibraryCoverAssetRef(
        assetId: 'comic/yamibo:target/source',
        revision: 2,
        kind: LibraryCoverAssetKind.source,
      );
      final targetImage = io.File('${coverRoot.path}/target.jpg');
      await targetImage.writeAsBytes(<int>[0xff, 0xd8, 3, 0xff, 0xd9]);
      await libraryCoverStore.installLocalFile(
        asset: targetAsset,
        sourcePath: targetImage.path,
      );
      await libraryCoverStore.installLocalFile(
        asset: oldTargetAsset,
        sourcePath: targetImage.path,
      );
      await db.insert(
        ComicLocalDb.libraryCoverMigrationsTable,
        const <String, Object?>{
          'asset_id': 'comic/yamibo:target/source',
          'revision': 2,
          'kind': 'installed',
          'completed_at': 1,
        },
      );

      await store.mergeDuplicateGroup(
        comicIds: const <String>{'yamibo:source', 'yamibo:target'},
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:target');
      expect(detail?.coverImageUrl, 'https://img.test/target.jpg');
      expect(detail?.coverRevision, 3);
      expect(
        await (await libraryCoverStore.fileFor(targetAsset)).exists(),
        isTrue,
      );
      expect(
        await (await libraryCoverStore.fileFor(oldTargetAsset)).exists(),
        isFalse,
      );
      expect(
        await db.query(
          ComicLocalDb.libraryCoverMigrationsTable,
          where: 'asset_id = ? AND revision = ?',
          whereArgs: const <Object>['comic/yamibo:target/source', 2],
        ),
        isEmpty,
      );
    });

    test(
      'source and custom covers are selected as independent bundles',
      () async {
        await _seedDuplicatePair(repository);
        final db = await dbFuture;
        await repository.addToShelf(
          comicId: 'yamibo:custom',
          tid: '9200',
          fid: '30',
          title: 'A Longer Custom Donor',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-9001-1-1.html', rawText: '1'),
            ],
            plainTextSummary: '',
          ),
        );
        await db.update(
          ComicLocalDb.comicsTable,
          <String, Object?>{
            'cover_image_url': 'https://img.test/source-bundle.jpg',
            'metadata_updated_at': 30,
          },
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:source'],
        );
        await db.update(
          ComicLocalDb.comicsTable,
          <String, Object?>{
            'custom_cover_image_url': 'https://img.test/custom-bundle.jpg',
            'custom_cover_revision': 4,
            'custom_cover_source_episode_id': 'yamibo:custom:9001',
            'custom_cover_source_image_index': 7,
            'custom_cover_source_image_url':
                'https://img.test/custom-origin.jpg',
            'custom_cover_focus_x': 0.25,
            'custom_cover_focus_y': -0.5,
            'metadata_updated_at': 20,
          },
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:custom'],
        );
        const donorCustomAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:custom/custom',
          revision: 4,
          kind: LibraryCoverAssetKind.custom,
        );
        final customImage = io.File('${coverRoot.path}/custom.jpg');
        await customImage.writeAsBytes(<int>[0xff, 0xd8, 4, 0xff, 0xd9]);
        await libraryCoverStore.installLocalFile(
          asset: donorCustomAsset,
          sourcePath: customImage.path,
        );

        await store.mergeDuplicateGroup(
          comicIds: const <String>{
            'yamibo:source',
            'yamibo:target',
            'yamibo:custom',
          },
        );

        final detail = await repository.getComicDetail(
          comicId: 'yamibo:target',
        );
        final coverColumns = (await db.query(
          ComicLocalDb.comicsTable,
          columns: const <String>[
            'cover_image_url',
            'cover_revision',
            'custom_cover_image_url',
            'custom_cover_revision',
          ],
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:target'],
        )).single;
        expect(
          coverColumns['cover_image_url'],
          'https://img.test/source-bundle.jpg',
        );
        expect(coverColumns['cover_revision'], 1);
        expect(
          coverColumns['custom_cover_image_url'],
          'https://img.test/custom-bundle.jpg',
        );
        expect(coverColumns['custom_cover_revision'], 1);
        expect(
          detail?.customCoverImageUrl,
          'https://img.test/custom-bundle.jpg',
        );
        expect(detail?.customCoverSourceEpisodeId, 'yamibo:target:9001');
        expect(detail?.customCoverSourceImageIndex, 7);
        expect(
          detail?.customCoverSourceImageUrl,
          'https://img.test/custom-origin.jpg',
        );
        expect(detail?.customCoverFocusX, 0.25);
        expect(detail?.customCoverFocusY, -0.5);
        const targetCustomAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:target/custom',
          revision: 1,
          kind: LibraryCoverAssetKind.custom,
        );
        expect(
          await (await libraryCoverStore.fileFor(targetCustomAsset)).exists(),
          isTrue,
        );
      },
    );

    test('URL-only source cover moves metadata without downloading', () async {
      await _seedDuplicatePair(repository);
      final db = await dbFuture;
      await db.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'cover_image_url': 'https://img.test/remote-only.jpg',
          'metadata_updated_at': 30,
        },
        where: 'comic_id = ?',
        whereArgs: const <Object>['yamibo:source'],
      );

      await store.mergeDuplicateGroup(
        comicIds: const <String>{'yamibo:source', 'yamibo:target'},
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:target');
      expect(detail?.coverRevision, 1);
      expect(detail?.coverImageUrl, 'https://img.test/remote-only.jpg');
      const targetAsset = LibraryCoverAssetRef(
        assetId: 'comic/yamibo:target/source',
        revision: 1,
        kind: LibraryCoverAssetKind.source,
      );
      expect(
        await (await libraryCoverStore.fileFor(targetAsset)).exists(),
        isFalse,
      );
      final marker = (await db.query(
        ComicLocalDb.libraryCoverMigrationsTable,
        where: 'asset_id = ?',
        whereArgs: const <Object>['comic/yamibo:target/source'],
      )).single;
      expect(marker['kind'], 'remote');
    });

    test('unrecoverable custom cover aborts before deleting comics', () async {
      await _seedDuplicatePair(repository);
      final db = await dbFuture;
      await db.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{'custom_cover_revision': 3},
        where: 'comic_id = ?',
        whereArgs: const <Object>['yamibo:source'],
      );

      await expectLater(
        store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:source', 'yamibo:target'},
        ),
        throwsStateError,
      );

      final rows = await db.query(
        ComicLocalDb.comicsTable,
        columns: const <String>['comic_id'],
        where: 'comic_id IN (?, ?)',
        whereArgs: const <Object>['yamibo:source', 'yamibo:target'],
      );
      expect(rows, hasLength(2));
      expect(
        await db.query(ComicLocalDb.comicCoverMergeOperationsTable),
        isEmpty,
      );
    });

    test('recovery rolls back preparing target revision', () async {
      await _seedDuplicatePair(repository);
      final db = await dbFuture;
      const targetAsset = LibraryCoverAssetRef(
        assetId: 'comic/yamibo:target/source',
        revision: 1,
        kind: LibraryCoverAssetKind.source,
      );
      final staged = io.File('${coverRoot.path}/staged.jpg');
      await staged.writeAsBytes(<int>[0xff, 0xd8, 1, 0xff, 0xd9]);
      await libraryCoverStore.installLocalFile(
        asset: targetAsset,
        sourcePath: staged.path,
      );
      await _insertJournal(
        db,
        operationId: 'preparing-op',
        state: 'preparing',
        targetAsset: targetAsset,
      );

      await store.recoverPendingCoverMerges();

      expect(
        await (await libraryCoverStore.fileFor(targetAsset)).exists(),
        isFalse,
      );
      expect(
        await db.query(ComicLocalDb.comicCoverMergeOperationsTable),
        isEmpty,
      );
    });

    test(
      'recovery finishes committed cleanup without deleting target',
      () async {
        await _seedDuplicatePair(repository);
        final db = await dbFuture;
        const sourceAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:source/source',
          revision: 1,
          kind: LibraryCoverAssetKind.source,
        );
        const targetAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:target/source',
          revision: 1,
          kind: LibraryCoverAssetKind.source,
        );
        final image = io.File('${coverRoot.path}/committed.jpg');
        await image.writeAsBytes(<int>[0xff, 0xd8, 1, 0xff, 0xd9]);
        await libraryCoverStore.installLocalFile(
          asset: sourceAsset,
          sourcePath: image.path,
        );
        await libraryCoverStore.installLocalFile(
          asset: targetAsset,
          sourcePath: image.path,
        );
        await db.update(
          ComicLocalDb.comicsTable,
          <String, Object?>{'cover_revision': 1},
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:target'],
        );
        await _insertJournal(
          db,
          operationId: 'committed-op',
          state: 'database_committed',
          targetAsset: targetAsset,
        );

        await store.recoverPendingCoverMerges();

        expect(
          await (await libraryCoverStore.fileFor(sourceAsset)).exists(),
          isFalse,
        );
        expect(
          await (await libraryCoverStore.fileFor(targetAsset)).exists(),
          isTrue,
        );
        expect(
          await db.query(ComicLocalDb.comicCoverMergeOperationsTable),
          isEmpty,
        );
      },
    );

    test(
      'committed cleanup failure keeps journal and later recovery converges',
      () async {
        await _seedDuplicatePair(repository);
        final db = await dbFuture;
        await db.update(
          ComicLocalDb.comicsTable,
          <String, Object?>{
            'cover_image_url': 'https://img.test/retry.jpg',
            'metadata_updated_at': 20,
          },
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:source'],
        );
        const sourceAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:source/source',
          revision: 1,
          kind: LibraryCoverAssetKind.source,
        );
        final image = io.File('${coverRoot.path}/retry.jpg');
        await image.writeAsBytes(<int>[0xff, 0xd8, 5, 0xff, 0xd9]);
        await libraryCoverStore.installLocalFile(
          asset: sourceAsset,
          sourcePath: image.path,
        );
        final failingStore = _FailDeleteOnceCoverStore(libraryCoverStore);
        final retryingMergeStore = ComicDuplicateMergeStore(
          dbFuture,
          coverStore: ComicCoverStore(dbFuture),
          libraryCoverStore: failingStore,
        );

        final result = await retryingMergeStore.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:source', 'yamibo:target'},
        );

        expect(result.targetComicId, 'yamibo:target');
        final pending = await db.query(
          ComicLocalDb.comicCoverMergeOperationsTable,
        );
        expect(pending.single['state'], 'database_committed');
        expect(
          await (await libraryCoverStore.fileFor(sourceAsset)).exists(),
          isTrue,
        );

        await retryingMergeStore.recoverPendingCoverMerges();

        expect(
          await db.query(ComicLocalDb.comicCoverMergeOperationsTable),
          isEmpty,
        );
        expect(
          await (await libraryCoverStore.fileFor(sourceAsset)).exists(),
          isFalse,
        );
        const targetAsset = LibraryCoverAssetRef(
          assetId: 'comic/yamibo:target/source',
          revision: 1,
          kind: LibraryCoverAssetKind.source,
        );
        expect(
          await (await libraryCoverStore.fileFor(targetAsset)).exists(),
          isTrue,
        );
      },
    );

    test(
      'mergeDuplicateGroup migrates reading progress library refs and cached images',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:source',
          tid: '3000',
          fid: '30',
          title: 'Source Duplicate Comic',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-3001-1-1.html',
                rawText: '1',
                episodeTitle: 'chapter 1',
              ),
            ],
            plainTextSummary: 'summary',
          ),
        );
        await repository.addToShelf(
          comicId: 'yamibo:target',
          tid: '4000',
          fid: '30',
          title: 'Short',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-3001-1-1.html',
                rawText: '1',
                episodeTitle: 'chapter 1',
              ),
            ],
            plainTextSummary: 'summary',
          ),
        );

        final stateRepository = LocalLibraryStateRepository(dbFuture);
        await stateRepository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'yamibo:source:3001',
          workId: 'yamibo:source',
          isRead: true,
          isDownloaded: true,
        );
        await stateRepository.upsertWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:source',
          lastReadEpisodeId: 'yamibo:source:3001',
          lastReadAt: DateTime.fromMillisecondsSinceEpoch(10),
          checkUpdatedAt: DateTime.fromMillisecondsSinceEpoch(20),
          fetchedUpdatedAt: DateTime.fromMillisecondsSinceEpoch(30),
          introText: 'source intro',
        );
        final tagId = await stateRepository.createTag(name: 'duplicate');
        await stateRepository.bindTagToWork(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:source',
          tagId: tagId,
        );
        await repository.updateLastReadProgress(
          comicId: 'yamibo:source',
          episodeId: 'yamibo:source:3001',
          imageIndex: 2,
          scrollOffset: 42,
        );

        final db = await dbFuture;
        await db.insert(ComicLocalDb.favoriteThreadsTable, <String, Object?>{
          'tid': '3000',
          'title': 'Source Duplicate Comic',
          'content_kind': 'comic',
          'work_id': 'yamibo:source',
          'first_seen_at': 1,
          'last_seen_at': 1,
        });
        await db.insert(ComicLocalDb.cachedImagesTable, <String, Object?>{
          'cache_key': 'comic-cover-source',
          'owner_type': 'comic',
          'owner_id': 'yamibo:source',
          'role': 'cover',
          'last_source_url': 'https://img.test/source-cover.jpg',
          'local_path': '/cache/source-cover.jpg',
          'bytes': 1024,
          'protected': 0,
          'created_at': 1,
          'updated_at': 1,
        });
        await db.insert(
          ComicLocalDb.comicSearchRefreshQueueTable,
          <String, Object?>{
            'comic_id': 'yamibo:source',
            'source_tid': '3000',
            'title': 'Source Duplicate Comic',
            'origin': 'favorite_sync',
            'status': 'pending',
            'attempts': 0,
            'available_at': 1,
            'created_at': 1,
            'updated_at': 1,
          },
        );

        final result = await store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:source', 'yamibo:target'},
        );

        final progress = await repository.getLastReadProgress(
          comicId: result.targetComicId,
        );
        final workState = await stateRepository.getWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: result.targetComicId,
        );
        final episodeState = await stateRepository.getEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'yamibo:target:3001',
        );
        final tags = await stateRepository.getWorkTags(
          moduleKey: LibraryModuleKey.comic,
          workId: result.targetComicId,
        );
        final favoriteRows = await db.query(
          ComicLocalDb.favoriteThreadsTable,
          columns: const <String>['work_id'],
          where: 'tid = ?',
          whereArgs: const <Object>['3000'],
        );
        final cachedRows = await db.query(
          ComicLocalDb.cachedImagesTable,
          columns: const <String>['owner_id'],
          where: 'cache_key = ?',
          whereArgs: const <Object>['comic-cover-source'],
        );
        final queueRows = await db.query(
          ComicLocalDb.comicSearchRefreshQueueTable,
          columns: const <String>['comic_id'],
          where: 'source_tid = ?',
          whereArgs: const <Object>['3000'],
        );

        expect(result.targetComicId, 'yamibo:target');
        expect(progress?.episodeId, 'yamibo:target:3001');
        expect(progress?.imageIndex, 2);
        expect(workState?.lastReadEpisodeId, 'yamibo:target:3001');
        expect(workState?.introText, 'source intro');
        expect(episodeState?.isRead, isTrue);
        expect(episodeState?.isDownloaded, isTrue);
        expect(tags.map((tag) => tag.name).toList(), <String>['duplicate']);
        expect(favoriteRows.single['work_id'], 'yamibo:target');
        expect(cachedRows.single['owner_id'], 'yamibo:target');
        expect(queueRows.single['comic_id'], 'yamibo:target');
      },
    );

    test(
      'mergeDuplicateGroup: shared episode with images on both sides → no duplicate images after merge',
      () async {
        // Both comics share source_tid '6000' and both have images seeded for it.
        // After merge, the surviving episode must have exactly those images — not doubled.
        await repository.addToShelf(
          comicId: 'yamibo:aa',
          tid: '6000',
          fid: '30',
          title: 'Long Duplicate Title',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[
              'https://img.test/p1.jpg',
              'https://img.test/p2.jpg',
            ],
            episodeLinks: <ComicEpisodeLink>[],
            plainTextSummary: '',
          ),
        );
        await repository.addToShelf(
          comicId: 'yamibo:bb',
          tid: '6000',
          fid: '30',
          title: 'Short',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[
              'https://img.test/p1.jpg',
              'https://img.test/p2.jpg',
            ],
            episodeLinks: <ComicEpisodeLink>[],
            plainTextSummary: '',
          ),
        );

        final result = await store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:aa', 'yamibo:bb'},
        );

        final db = await dbFuture;
        final images = await db.query(
          ComicLocalDb.episodeImagesTable,
          where: 'episode_id = ?',
          whereArgs: <Object>['${result.targetComicId}:6000'],
          orderBy: 'image_index ASC',
        );
        expect(images, hasLength(2));
        expect(images[0]['image_url'], 'https://img.test/p1.jpg');
        expect(images[1]['image_url'], 'https://img.test/p2.jpg');
      },
    );

    test(
      'mergeDuplicateGroup keeps hidden intent and demotes manual duplicates',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:merge-long-title',
          tid: '7000',
          fid: '30',
          title: 'Long Duplicate Title',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-7001-1-1.html', rawText: '1'),
            ],
            plainTextSummary: '',
          ),
        );
        await repository.addToShelf(
          comicId: 'yamibo:merge',
          tid: '7000',
          fid: '30',
          title: 'Short',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            // 保留另一条可见章节，满足“不能隐藏最后一个可见章节”的契约，
            // 同时让本测试专注验证重复章节的隐藏意图是否被合并保留。
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-7002-1-1.html', rawText: '2'),
            ],
            plainTextSummary: '',
          ),
        );
        // 目标侧只手动添加了这一话，来源侧靠解析发现了同一个 tid。
        await repository.addManualEpisode(
          comicId: 'yamibo:merge',
          sourceTid: '7001',
          sourceUrl: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7001',
        );
        final visibility = await repository.setEpisodeHidden(
          comicId: 'yamibo:merge',
          episodeId: 'yamibo:merge:7001',
          isHidden: true,
        );
        expect(visibility.code, ComicEpisodeVisibilityUpdateCode.updated);

        final result = await store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:merge-long-title', 'yamibo:merge'},
        );
        expect(result.targetComicId, 'yamibo:merge');

        final merged = await repository.getManagedComicEpisodes(
          comicId: 'yamibo:merge',
        );
        final episode = merged.firstWhere((item) => item.sourceTid == '7001');
        expect(episode.isHidden, isTrue);
        expect(episode.isManual, isFalse);
      },
    );

    test(
      'mergeDuplicateGroup keeps a rename and still lets it fall back',
      () async {
        // 重命名落在被合并掉的那一侧，来源名则是目标侧更短、来源侧更长。
        await repository.addToShelf(
          comicId: 'yamibo:rename-long-title',
          tid: '8000',
          fid: '30',
          title: 'Long Duplicate Title',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-8001-1-1.html',
                rawText: '8',
                episodeTitle: '第八话 完整名',
              ),
            ],
            plainTextSummary: '',
          ),
        );
        await repository.addToShelf(
          comicId: 'yamibo:rename',
          tid: '8000',
          fid: '30',
          title: 'Short',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-8001-1-1.html',
                rawText: '8',
                episodeTitle: '8',
              ),
            ],
            plainTextSummary: '',
          ),
        );
        await repository.setEpisodeCustomTitle(
          comicId: 'yamibo:rename-long-title',
          episodeId: 'yamibo:rename-long-title:8001',
          customTitle: '我改的名字',
        );

        final result = await store.mergeDuplicateGroup(
          comicIds: const <String>{'yamibo:rename-long-title', 'yamibo:rename'},
        );
        expect(result.targetComicId, 'yamibo:rename');

        final merged = await repository.getManagedComicEpisodes(
          comicId: 'yamibo:rename',
        );
        final episode = merged.firstWhere((item) => item.sourceTid == '8001');
        expect(episode.customEpisodeTitle, '我改的名字');
        expect(episode.episodeTitle, '我改的名字');
        // 来源名按“信息量更大者胜出”换成了来源侧那个，展示名要跟着重算，
        // 否则清空重命名会退回一个已经被替换掉的旧来源名。
        expect(episode.sourceEpisodeTitle, '第八话 完整名');

        await repository.setEpisodeCustomTitle(
          comicId: 'yamibo:rename',
          episodeId: 'yamibo:rename:8001',
          customTitle: null,
        );
        final restored = await repository.getManagedComicEpisodes(
          comicId: 'yamibo:rename',
        );
        expect(
          restored.firstWhere((item) => item.sourceTid == '8001').episodeTitle,
          '第八话 完整名',
        );
      },
    );
  });
}

Future<void> _seedDuplicatePair(LocalComicRepository repository) async {
  await repository.addToShelf(
    comicId: 'yamibo:source',
    tid: '9000',
    fid: '30',
    title: 'Long Duplicate Source',
    parsedPost: const ParsedComicPost(
      imageUrls: <String>[],
      episodeLinks: <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-9001-1-1.html', rawText: '1'),
      ],
      plainTextSummary: '',
    ),
  );
  await repository.addToShelf(
    comicId: 'yamibo:target',
    tid: '9100',
    fid: '30',
    title: 'Short',
    parsedPost: const ParsedComicPost(
      imageUrls: <String>[],
      episodeLinks: <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-9001-1-1.html', rawText: '1'),
      ],
      plainTextSummary: '',
    ),
  );
}

Future<void> _insertJournal(
  Database db, {
  required String operationId,
  required String state,
  required LibraryCoverAssetRef targetAsset,
}) async {
  await db
      .insert(ComicLocalDb.comicCoverMergeOperationsTable, <String, Object?>{
        'operation_id': operationId,
        'target_comic_id': 'yamibo:target',
        'state': state,
        'created_at': 1,
        'updated_at': 1,
      });
  await db.insert(ComicLocalDb.comicCoverMergeMembersTable, <String, Object?>{
    'operation_id': operationId,
    'source_comic_id': 'yamibo:source',
  });
  await db.insert(ComicLocalDb.comicCoverMergeAssetsTable, <String, Object?>{
    'operation_id': operationId,
    'kind': 'source',
    'source_comic_id': 'yamibo:source',
    'source_asset_id': 'comic/yamibo:source/source',
    'source_revision': 1,
    'target_asset_id': targetAsset.assetId,
    'target_revision': targetAsset.revision,
    'mode': 'installed',
  });
}

class _NoCoverDownload implements LibraryCoverDownloader {
  const _NoCoverDownload();

  @override
  Future<void> download({required String url, required String targetPath}) {
    throw StateError('duplicate merge must not download covers');
  }
}

class _FailDeleteOnceCoverStore implements LibraryCoverStore {
  _FailDeleteOnceCoverStore(this.delegate);

  final LibraryCoverStore delegate;
  bool _shouldFailDelete = true;

  @override
  Future<int> calculateUsageBytes() => delegate.calculateUsageBytes();

  @override
  Future<void> deleteAsset(String assetId) {
    if (_shouldFailDelete) {
      _shouldFailDelete = false;
      throw io.FileSystemException('simulated cleanup failure');
    }
    return delegate.deleteAsset(assetId);
  }

  @override
  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset) {
    return delegate.deleteOlderRevisions(asset);
  }

  @override
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset) {
    return delegate.ensureAvailable(asset);
  }

  @override
  Future<io.File> fileFor(LibraryCoverAssetRef asset) {
    return delegate.fileFor(asset);
  }

  @override
  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  }) {
    return delegate.installLocalFile(asset: asset, sourcePath: sourcePath);
  }

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) {
    return delegate.invalidate(asset);
  }
}
