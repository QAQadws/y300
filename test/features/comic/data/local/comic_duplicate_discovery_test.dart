import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/presentation/adapters/comic_shelf_adapter.dart';
import 'package:y300/features/favorites/data/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

import '../../../../test_support/unavailable_library_cover_store.dart';
import '../../domain/services/comic_title_parser_cases.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Comic duplicate discovery', () {
    const databaseName = 'comic_duplicate_discovery_test.db';
    late Database db;
    late LocalComicRepository repository;
    late ComicDuplicateMergeService service;
    late LocalLibraryStateRepository stateRepository;
    late LibraryShelfRefreshBus bus;

    setUp(() async {
      await deleteDatabase(databaseName);
      db = await ComicLocalDb.open(databaseName: databaseName);
      repository = LocalComicRepository(
        Future.value(db),
        libraryCoverStore: const UnavailableLibraryCoverStore(),
      );
      service = ComicDuplicateMergeService(repository: repository);
      stateRepository = LocalLibraryStateRepository(Future.value(db));
      bus = LibraryShelfRefreshBus();
    });

    tearDown(() async {
      bus.dispose();
      await db.close();
      await deleteDatabase(databaseName);
    });

    Future<void> seed(
      String tid,
      ComicDuplicateMetadataFixture metadata, {
      String? chapterTid,
    }) async {
      await repository.addToShelf(
        comicId: 'yamibo:$tid',
        tid: tid,
        fid: '30',
        title: metadata.title,
        parsedPost: ParsedComicPost(
          imageUrls: const [],
          episodeLinks: [
            ComicEpisodeLink(
              url: 'thread-${chapterTid ?? tid}-1-1.html',
              rawText: '',
            ),
          ],
          plainTextSummary: '',
          inferredAuthor: metadata.author,
        ),
      );
    }

    for (final testCase in comicDuplicateMetadataCases) {
      test('stored metadata: ${testCase.id}', () async {
        await seed('100', testCase.left);
        await seed('200', testCase.right);

        final groups = await repository.findDuplicateGroups();
        if (testCase.matches) {
          expect(groups.single.comicIds, {'yamibo:100', 'yamibo:200'});
          expect(groups.single.sharedTids, isEmpty);
        } else {
          expect(groups, isEmpty);
        }
      });
    }

    test(
      'metadata discovery does not require a source or episode tid',
      () async {
        await seed('100', comicDuplicateMetadataBase);
        await seed('200', comicDuplicateMetadataBase);
        await db.delete(ComicLocalDb.episodesTable);
        await db.update(ComicLocalDb.comicsTable, {'source_tid': ''});

        final groups = await repository.findDuplicateGroups(
          comicId: 'yamibo:200',
        );

        expect(groups.single.comicIds, {'yamibo:100', 'yamibo:200'});
        expect(groups.single.sharedTids, isEmpty);
      },
    );

    test(
      'effective custom title and author override source metadata',
      () async {
        await seed('100', comicDuplicateMetadataBase);
        await seed('200', comicDuplicateMetadataOther);
        await seed('300', comicDuplicateMetadataBase);
        await repository.updateCustomMetadata(
          comicId: 'yamibo:200',
          customTitle: comicDuplicateMetadataBase.title,
          customAuthor: comicDuplicateMetadataBase.author,
        );
        await repository.updateCustomMetadata(
          comicId: 'yamibo:300',
          customTitle: comicDuplicateMetadataBase.title,
          customAuthor: comicDuplicateMetadataOther.author,
        );

        final groups = await repository.findDuplicateGroups();
        final detail = await repository.getComicDetail(comicId: 'yamibo:200');

        expect(groups.single.comicIds, {'yamibo:100', 'yamibo:200'});
        expect(detail?.sourceTitle, comicDuplicateMetadataOther.title);
        expect(detail?.sourceAuthor, comicDuplicateMetadataOther.author);

        await repository.clearCustomMetadata(
          comicId: 'yamibo:200',
          title: true,
          author: true,
        );
        expect(await repository.findDuplicateGroups(), isEmpty);
      },
    );

    test(
      'mixed links merge locally then globally without repeated changes',
      () async {
        await seed('100', comicDuplicateMetadataBase, chapterTid: '101');
        await seed('200', comicDuplicateMetadataBase, chapterTid: '201');
        await seed('201', comicDuplicateMetadataOther, chapterTid: '301');
        await seed('400', comicDuplicateMetadataPlain);
        await seed('500', comicDuplicateMetadataPlain);

        final groups = await repository.findDuplicateGroups();
        expect(groups, hasLength(2));
        final local = await repository.findDuplicateGroups(
          comicId: ' yamibo:201 ',
        );
        expect(local.single.comicIds, {
          'yamibo:100',
          'yamibo:200',
          'yamibo:201',
        });
        expect(local.single.sharedTids, {'201'});
        expect(
          await repository.findDuplicateGroups(comicId: 'missing'),
          isEmpty,
        );

        final merged = await service.mergeComic(comicId: 'yamibo:201');
        expect(merged.targetComicId, 'yamibo:100');
        expect(merged.mergedComicIds, {'yamibo:200', 'yamibo:201'});
        final remaining = await repository.findDuplicateGroups();
        expect(remaining.single.comicIds, {'yamibo:400', 'yamibo:500'});

        final summary = await service.mergeAllDuplicates();
        expect(summary.mergedGroupCount, 1);
        expect(summary.removedComicCount, 1);
        expect(await repository.findDuplicateGroups(), isEmpty);
        expect((await service.mergeAllDuplicates()).changed, isFalse);
        expect(
          (await service.mergeComic(comicId: 'yamibo:100')).changed,
          isFalse,
        );
      },
    );

    test(
      'shelf menu merges disjoint chapters and preserves user state',
      () async {
        await seed('100', comicDuplicateMetadataPlain, chapterTid: '101');
        await seed('200', comicDuplicateMetadataFormatted, chapterTid: '201');
        final categoryId = await repository.createCategory(name: 'follow');
        await repository.moveComicToCategory(
          comicId: 'yamibo:200',
          fromCategoryId: 'default',
          toCategoryId: categoryId,
        );
        await stateRepository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'yamibo:200:201',
          workId: 'yamibo:200',
          isRead: true,
          isDownloaded: true,
          isBookmarked: true,
        );
        await stateRepository.upsertWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:200',
          lastReadEpisodeId: 'yamibo:200:201',
          introText: 'saved intro',
        );
        await repository.updateLastReadProgress(
          comicId: 'yamibo:200',
          episodeId: 'yamibo:200:201',
          imageIndex: 2,
          scrollOffset: 42,
        );
        final tagId = await stateRepository.createTag(name: 'follow');
        await stateRepository.bindTagToWork(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:200',
          tagId: tagId,
        );
        await db.insert(ComicLocalDb.favoriteThreadsTable, {
          'tid': '200',
          'title': comicDuplicateMetadataFormatted.title,
          'content_kind': 'comic',
          'work_id': 'yamibo:200',
          'first_seen_at': 1,
          'last_seen_at': 1,
        });
        final adapter = ComicShelfAdapter(
          repository,
          stateRepository: stateRepository,
          duplicateMergeService: service,
          shelfRefreshBus: bus,
        );

        final result = await adapter.runMenuAction(
          LibraryShelfMenuAction.mergeDuplicates,
        );

        expect(result.code, ShelfModuleActionOutcomeCode.success);
        expect(result.affectedCount, 1);
        expect(await repository.getComicDetail(comicId: 'yamibo:200'), isNull);
        final detail = await repository.getComicDetail(comicId: 'yamibo:100');
        expect(detail?.title, comicDuplicateMetadataPlain.title);
        final episodes = await repository.getComicEpisodes(
          comicId: 'yamibo:100',
          descending: false,
        );
        expect(episodes.map((episode) => episode.sourceTid), ['101', '201']);
        final progress = await repository.getLastReadProgress(
          comicId: 'yamibo:100',
        );
        expect(progress?.episodeId, 'yamibo:100:201');
        expect(progress?.imageIndex, 2);
        expect(progress?.scrollOffset, 42);
        final episodeState = await stateRepository.getEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'yamibo:100:201',
        );
        expect(episodeState?.isRead, isTrue);
        expect(episodeState?.isDownloaded, isTrue);
        expect(episodeState?.isBookmarked, isTrue);
        final workState = await stateRepository.getWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:100',
        );
        expect(workState?.lastReadEpisodeId, 'yamibo:100:201');
        expect(workState?.introText, 'saved intro');
        final tags = await stateRepository.getWorkTags(
          moduleKey: LibraryModuleKey.comic,
          workId: 'yamibo:100',
        );
        expect(tags.map((tag) => tag.tagId), [tagId]);
        final categoryItems = await repository.getShelfItems(
          categoryId: categoryId,
        );
        expect(categoryItems.map((item) => item.comicId), ['yamibo:100']);
        final favorites = await db.query(ComicLocalDb.favoriteThreadsTable);
        expect(favorites.single['work_id'], 'yamibo:100');
        expect(bus.signal.value?.source, LibraryMutationSource.duplicateMerge);
        expect(
          bus.signal.value?.modules,
          containsAll([LibraryModuleKey.comic, LibraryModuleKey.favorite]),
        );
        expect(
          (await adapter.runMenuAction(
            LibraryShelfMenuAction.mergeDuplicates,
          )).code,
          ShelfModuleActionOutcomeCode.noChange,
        );
      },
    );

    for (final mergeAll in [false, true]) {
      test(
        'favorite ${mergeAll ? 'full' : 'incremental'} sync merges metadata-only groups',
        () async {
          await seed('100', comicDuplicateMetadataPlain);
          await seed('200', comicDuplicateMetadataFormatted);
          final runner = DefaultLibraryPostIngestTaskRunner(
            comicDuplicateMergeService: service,
            shelfRefreshBus: bus,
          );
          final task = mergeAll
              ? const ComicDuplicateMergeAllTask()
              : const ComicDuplicateMergeTask(comicId: 'yamibo:200');

          final report = await runner.runAll([task]);

          expect(report.failures, isEmpty);
          expect(report.completed, [task]);
          expect(report.resolvedWorkId, mergeAll ? isNull : 'yamibo:100');
          expect(
            await repository.getComicDetail(comicId: 'yamibo:200'),
            isNull,
          );
          expect(await repository.findDuplicateGroups(), isEmpty);
          expect(
            bus.signal.value?.source,
            LibraryMutationSource.duplicateMerge,
          );
          expect(
            bus.signal.value?.payload[mergeAll
                ? 'removedComicCount'
                : 'targetComicId'],
            mergeAll ? 1 : 'yamibo:100',
          );
          final repeated = await runner.runAll([
            if (mergeAll)
              const ComicDuplicateMergeAllTask()
            else
              const ComicDuplicateMergeTask(comicId: 'yamibo:100'),
          ]);
          expect(repeated.failures, isEmpty);
          expect(repeated.resolvedWorkId, isNull);
        },
      );
    }
  });
}
