import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_duplicate_merge_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ComicDuplicateMergeStore', () {
    const databaseName = 'comic_duplicate_merge_store_test.db';

    late Future<Database> dbFuture;
    late LocalComicRepository repository;
    late ComicDuplicateMergeStore store;

    setUp(() async {
      await deleteDatabase(databaseName);
      dbFuture = ComicLocalDb.open(databaseName: databaseName);
      repository = LocalComicRepository(dbFuture);
      store = ComicDuplicateMergeStore(
        dbFuture,
        coverStore: ComicCoverStore(dbFuture),
      );
    });

    test('mergeDuplicateGroup chooses shortest title target and keeps shelf membership', () async {
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

      final customCategoryId = await repository.createCategory(name: 'follow');
      await repository.moveComicToCategory(
        comicId: 'yamibo:1000',
        fromCategoryId: 'default',
        toCategoryId: customCategoryId,
      );

      final result = await store.mergeDuplicateGroup(
        comicIds: const <String>{'yamibo:1000', 'yamibo:2000'},
      );

      final detail = await repository.getComicDetail(comicId: result.targetComicId);
      final episodes = await repository.getComicEpisodes(
        comicId: result.targetComicId,
        descending: false,
      );
      final defaultItems = await repository.getShelfItems(categoryId: 'default');
      final customItems = await repository.getShelfItems(categoryId: customCategoryId);

      expect(result.targetComicId, 'yamibo:2000');
      expect(result.targetTitle, 'Short');
      expect(detail?.title, 'Short');
      expect(episodes.map((episode) => episode.sourceTid).toList(), <String>[
        '1001',
        '1002',
        '1003',
      ]);
      expect(defaultItems.map((item) => item.comicId).toSet(), <String>{'yamibo:2000'});
      expect(customItems.map((item) => item.comicId).toSet(), <String>{'yamibo:2000'});
    });

    test('mergeDuplicateGroup migrates reading progress library refs and cached images', () async {
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
      await db.insert(
        ComicLocalDb.favoriteThreadsTable,
        <String, Object?>{
          'tid': '3000',
          'title': 'Source Duplicate Comic',
          'content_kind': 'comic',
          'work_id': 'yamibo:source',
          'first_seen_at': 1,
          'last_seen_at': 1,
        },
      );
      await db.insert(
        ComicLocalDb.cachedImagesTable,
        <String, Object?>{
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
        },
      );
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

      final progress = await repository.getLastReadProgress(comicId: result.targetComicId);
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
    });

    test('mergeDuplicateGroup: shared episode with images on both sides → no duplicate images after merge', () async {
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
    });
  });
}
