import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Database;
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalLibraryStateRepository', () {
    late LocalLibraryStateRepository repository;
    late Database db;
    const dbName = 'comic_shelf_test_library_state_repo.db';

    setUp(() async {
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      repository = LocalLibraryStateRepository(dbFuture);
      db = await dbFuture;
    });

    tearDown(() async {
      await deleteDatabase(dbName);
    });

    test('can upsert and query work state', () async {
      await repository.upsertWorkState(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
        lastReadEpisodeId: 'e1',
        introText: 'intro',
      );

      final state = await repository.getWorkState(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );

      expect(state, isNotNull);
      expect(state!.lastReadEpisodeId, 'e1');
      expect(state.introText, 'intro');
    });

    test(
      'partial work state updates preserve freshness and intro metadata',
      () async {
        final checkedAt = DateTime(2026, 6, 1);
        final fetchedAt = DateTime(2026, 6, 2);
        await repository.upsertWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:100',
          checkUpdatedAt: checkedAt,
          fetchedUpdatedAt: fetchedAt,
          introText: 'source intro',
        );

        await repository.upsertWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:100',
          lastReadEpisodeId: 'episode-2',
          lastReadAt: DateTime(2026, 6, 3),
        );

        final state = await repository.getWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:100',
        );

        expect(state, isNotNull);
        expect(state!.lastReadEpisodeId, 'episode-2');
        expect(state.checkUpdatedAt, checkedAt);
        expect(state.fetchedUpdatedAt, fetchedAt);
        expect(state.introText, 'source intro');
      },
    );

    test('can upsert and count episode states', () async {
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: 'ep1',
        workId: 'novel:49:1',
        isRead: false,
        isDownloaded: true,
      );
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: 'ep2',
        workId: 'novel:49:1',
        isRead: true,
      );

      final unread = await repository.countUnreadEpisodes(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:1',
      );
      final read = await repository.countReadEpisodes(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:1',
      );
      final downloaded = await repository.countDownloadedEpisodes(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:1',
      );

      expect(unread, 1);
      expect(read, 1);
      expect(downloaded, 1);
    });

    test('can detect bookmarked episodes without using read state', () async {
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: 'ep1',
        workId: 'novel:49:1',
        isBookmarked: true,
      );
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: 'ep2',
        workId: 'novel:49:2',
        isRead: false,
      );

      expect(
        await repository.hasAnyBookmarkedEpisode(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel:49:1',
        ),
        isTrue,
      );
      expect(
        await repository.hasAnyBookmarkedEpisode(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel:49:2',
        ),
        isFalse,
      );
    });

    test('marking episode unread clears readAt', () async {
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'ep1',
        workId: 'comic:1',
        isRead: true,
        readAt: DateTime(2026, 5, 12),
      );
      await repository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'ep1',
        workId: 'comic:1',
        isRead: false,
        readAt: null,
      );

      final state = await repository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'ep1',
      );

      expect(state, isNotNull);
      expect(state!.isRead, isFalse);
      expect(state.readAt, isNull);
    });

    test(
      'setWorksReadState fills comic episode states and preserves flags',
      () async {
        await _insertComic(db, comicId: 'comic:batch-a', title: 'Batch A');
        await _insertComic(db, comicId: 'comic:batch-b', title: 'Batch B');
        await _insertComicEpisode(
          db,
          episodeId: 'comic:batch-a:1',
          comicId: 'comic:batch-a',
          orderIndex: 0,
        );
        await _insertComicEpisode(
          db,
          episodeId: 'comic:batch-a:2',
          comicId: 'comic:batch-a',
          orderIndex: 1,
        );
        await _insertComicEpisode(
          db,
          episodeId: 'comic:batch-b:1',
          comicId: 'comic:batch-b',
          orderIndex: 0,
        );
        final downloadedAt = DateTime(2026, 5, 1);
        await repository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'comic:batch-a:2',
          workId: 'comic:batch-a',
          isDownloaded: true,
          isBookmarked: true,
          downloadedAt: downloadedAt,
        );

        await repository.setWorksReadState(
          moduleKey: LibraryModuleKey.comic,
          workIds: <String>{'comic:batch-a'},
          isRead: true,
          readAt: DateTime(2026, 5, 2),
        );

        expect(
          await repository.countReadEpisodes(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:batch-a',
          ),
          2,
        );
        expect(
          await repository.countUnreadEpisodes(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:batch-a',
          ),
          0,
        );
        final existing = await repository.getEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'comic:batch-a:2',
        );
        expect(existing?.isDownloaded, isTrue);
        expect(existing?.isBookmarked, isTrue);
        expect(existing?.downloadedAt, downloadedAt);
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic:batch-b:1',
          ),
          isNull,
        );

        await repository.setWorksReadState(
          moduleKey: LibraryModuleKey.comic,
          workIds: <String>{'comic:batch-a'},
          isRead: false,
        );

        expect(
          await repository.countReadEpisodes(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:batch-a',
          ),
          0,
        );
        expect(
          await repository.countUnreadEpisodes(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:batch-a',
          ),
          2,
        );
        final unread = await repository.getEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'comic:batch-a:1',
        );
        expect(unread?.isRead, isFalse);
        expect(unread?.readAt, isNull);
      },
    );

    test(
      'setWorksReadState only updates novel episodes for target module',
      () async {
        await _insertNovel(db, novelId: 'novel:batch-a', title: 'Novel A');
        await _insertNovel(db, novelId: 'novel:batch-b', title: 'Novel B');
        await _insertNovelEpisode(
          db,
          episodeId: 'novel:batch-a:1',
          novelId: 'novel:batch-a',
          contentType: 'novel',
          orderIndex: 0,
        );
        await _insertNovelEpisode(
          db,
          episodeId: 'novel:batch-a:comic-like',
          novelId: 'novel:batch-a',
          contentType: 'comic',
          orderIndex: 1,
        );
        await _insertNovelEpisode(
          db,
          episodeId: 'novel:batch-b:1',
          novelId: 'novel:batch-b',
          contentType: 'novel',
          orderIndex: 0,
        );
        await _insertComic(
          db,
          comicId: 'novel:batch-a',
          title: 'Same id comic',
        );
        await _insertComicEpisode(
          db,
          episodeId: 'comic:same-id:1',
          comicId: 'novel:batch-a',
          orderIndex: 0,
        );

        await repository.setWorksReadState(
          moduleKey: LibraryModuleKey.novel,
          workIds: <String>{'novel:batch-a'},
          isRead: true,
          readAt: DateTime(2026, 5, 3),
        );

        expect(
          await repository.countReadEpisodes(
            moduleKey: LibraryModuleKey.novel,
            workId: 'novel:batch-a',
          ),
          1,
        );
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.novel,
            episodeId: 'novel:batch-a:comic-like',
          ),
          isNull,
        );
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.novel,
            episodeId: 'novel:batch-b:1',
          ),
          isNull,
        );
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic:same-id:1',
          ),
          isNull,
        );
      },
    );

    test(
      'purgeWorkState removes only target work state, episode state and tags',
      () async {
        await repository.upsertWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'comic:purge',
          lastReadEpisodeId: 'comic-ep-1',
        );
        await repository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'comic-ep-1',
          workId: 'comic:purge',
          isRead: true,
        );
        final comicTagId = await repository.createTag(name: '待清理');
        await repository.bindTagToWork(
          moduleKey: LibraryModuleKey.comic,
          workId: 'comic:purge',
          tagId: comicTagId,
        );

        await repository.upsertWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'comic:keep',
          lastReadEpisodeId: 'comic-ep-2',
        );
        await repository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'comic-ep-2',
          workId: 'comic:keep',
          isRead: false,
        );

        await repository.upsertWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'comic:purge',
          lastReadEpisodeId: 'novel-ep-1',
        );
        await repository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.novel,
          episodeId: 'novel-ep-1',
          workId: 'comic:purge',
          isRead: false,
        );
        final novelTagId = await repository.createTag(name: '保留');
        await repository.bindTagToWork(
          moduleKey: LibraryModuleKey.novel,
          workId: 'comic:purge',
          tagId: novelTagId,
        );

        await repository.purgeWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'comic:purge',
        );

        expect(
          await repository.getWorkState(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:purge',
          ),
          isNull,
        );
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic-ep-1',
          ),
          isNull,
        );
        expect(
          await repository.hasAnyTag(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:purge',
          ),
          isFalse,
        );

        expect(
          await repository.getWorkState(
            moduleKey: LibraryModuleKey.comic,
            workId: 'comic:keep',
          ),
          isNotNull,
        );
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic-ep-2',
          ),
          isNotNull,
        );
        expect(
          await repository.getWorkState(
            moduleKey: LibraryModuleKey.novel,
            workId: 'comic:purge',
          ),
          isNotNull,
        );
        expect(
          await repository.getEpisodeState(
            moduleKey: LibraryModuleKey.novel,
            episodeId: 'novel-ep-1',
          ),
          isNotNull,
        );
        expect(
          await repository.hasAnyTag(
            moduleKey: LibraryModuleKey.novel,
            workId: 'comic:purge',
          ),
          isTrue,
        );
      },
    );

    test('can save and load display settings', () async {
      await repository.upsertDisplaySettings(
        moduleKey: LibraryModuleKey.comic,
        displayMode: LibraryDisplayMode.grid,
        gridColumns: 2,
      );

      final settings = await repository.getDisplaySettings(
        moduleKey: LibraryModuleKey.comic,
        defaultDisplayMode: LibraryDisplayMode.grid,
      );
      expect(settings.displayMode, LibraryDisplayMode.grid);
      expect(settings.gridColumns, 2);
    });

    test('can manage tags and work binding', () async {
      final tagId = await repository.createTag(name: '待看');
      await repository.bindTagToWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
        tagId: tagId,
      );

      final hasAnyTag = await repository.hasAnyTag(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );
      final tags = await repository.getWorkTags(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );

      expect(hasAnyTag, isTrue);
      expect(tags.length, 1);
      expect(tags.first.name, '待看');

      await repository.unbindTagFromWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
        tagId: tagId,
      );
      final afterUnbind = await repository.hasAnyTag(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:100',
      );
      expect(afterUnbind, isFalse);
    });
  });
}

Future<void> _insertComic(
  Database db, {
  required String comicId,
  required String title,
}) {
  final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
  return db.insert(ComicLocalDb.comicsTable, <String, Object?>{
    'comic_id': comicId,
    'source_tid': comicId,
    'source_fid': '30',
    'title': title,
    'created_at': now,
    'updated_at': now,
  });
}

Future<void> _insertComicEpisode(
  Database db, {
  required String episodeId,
  required String comicId,
  required int orderIndex,
}) {
  return db.insert(ComicLocalDb.episodesTable, <String, Object?>{
    'episode_id': episodeId,
    'comic_id': comicId,
    'episode_title': 'Episode $orderIndex',
    'source_tid': '$orderIndex',
    'source_url': 'thread-$orderIndex-1-1.html',
    'order_index': orderIndex,
  });
}

Future<void> _insertNovel(
  Database db, {
  required String novelId,
  required String title,
}) {
  return db.insert(ComicLocalDb.worksTable, <String, Object?>{
    'work_id': novelId,
    'content_type': 'novel',
    'source_tid': novelId,
    'source_fid': '75',
    'title': title,
    'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
  });
}

Future<void> _insertNovelEpisode(
  Database db, {
  required String episodeId,
  required String novelId,
  required String contentType,
  required int orderIndex,
}) {
  return db.insert(ComicLocalDb.workEpisodesTable, <String, Object?>{
    'episode_id': episodeId,
    'work_id': novelId,
    'content_type': contentType,
    'source_tid': novelId,
    'source_pid': '$orderIndex',
    'episode_title': 'Chapter $orderIndex',
    'order_index': orderIndex,
  });
}
