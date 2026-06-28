import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_snapshot_store.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ComicSnapshotStore', () {
    const databaseName = 'comic_snapshot_store_test.db';

    late Future<Database> dbFuture;
    late LocalComicRepository repository;
    late ComicSnapshotStore store;

    setUp(() async {
      await deleteDatabase(databaseName);
      dbFuture = ComicLocalDb.open(databaseName: databaseName);
      repository = LocalComicRepository(dbFuture);
      store = ComicSnapshotStore(dbFuture);
    });

    test('queryShelfSnapshot aggregates unread read downloaded and tags', () async {
      await repository.addToShelf(
        comicId: 'yamibo:900',
        tid: '900',
        fid: '30',
        title: 'Aggregate Comic',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-901-1-1.html',
              rawText: '1',
              episodeTitle: 'chapter 1',
            ),
            ComicEpisodeLink(
              url: 'thread-902-1-1.html',
              rawText: '2',
              episodeTitle: 'chapter 2',
            ),
          ],
          plainTextSummary: 'summary',
          inferredAuthor: 'authorS',
        ),
      );

      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:900:901',
        workId: 'yamibo:900',
        isRead: false,
        isDownloaded: true,
      );
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:900:902',
        workId: 'yamibo:900',
        isRead: true,
      );
      final tagId = await stateRepository.createTag(name: 'follow');
      await stateRepository.bindTagToWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:900',
        tagId: tagId,
      );

      final snapshot = await store.queryShelfSnapshot(
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );
      final item = snapshot.itemsByCategory['default']!.single;

      expect(snapshot.categories.single.categoryId, 'default');
      expect(snapshot.visibleMatchCountByCategory['default'], 1);
      expect(item.title, 'Aggregate Comic');
      expect(item.unreadCount, 1);
      expect(item.readChapterCount, 1);
      expect(item.totalChapterCount, 2);
      expect(item.isDownloaded, isTrue);
      expect(item.hasTags, isTrue);
    });

    test('getShelfWorkStats treats missing episode state as unread', () async {
      await repository.addToShelf(
        comicId: 'yamibo:910',
        tid: '910',
        fid: '30',
        title: 'No State Comic',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-911-1-1.html',
              rawText: '1',
              episodeTitle: 'chapter 1',
            ),
            ComicEpisodeLink(
              url: 'thread-912-1-1.html',
              rawText: '2',
              episodeTitle: 'chapter 2',
            ),
            ComicEpisodeLink(
              url: 'thread-913-1-1.html',
              rawText: '3',
              episodeTitle: 'chapter 3',
            ),
          ],
          plainTextSummary: 'summary',
        ),
      );

      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:910:911',
        workId: 'yamibo:910',
        isRead: true,
      );

      final stats = await store.getShelfWorkStats(comicId: 'yamibo:910');

      expect(stats.totalCount, 3);
      expect(stats.readCount, 1);
      expect(stats.unreadCount, 2);
      expect(stats.downloadedCount, 0);
    });
  });
}
