import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late LocalNovelRepository repository;
  late LocalLibraryStateRepository shared;
  setUp(() async {
    db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    repository = LocalNovelRepository(Future.value(db));
    shared = LocalLibraryStateRepository(Future.value(db));
  });
  tearDown(() async => db.close());

  NovelReadingProgress position(String episode, int revision) =>
      NovelReadingProgress(
        novelId: 'novel',
        episodeId: episode,
        scrollOffset: revision * 100,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(revision),
        progressPercent: revision / 10,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
      );

  test(
    'positions are independent and compatibility query follows atomic recent pointer',
    () async {
      await repository.commitProgress(progress: position('a', 2));
      await repository.commitProgress(progress: position('b', 4));
      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.progressByEpisode.keys, unorderedEquals(['a', 'b']));
      expect(state.progressByEpisode['a']!.progressPercent, .2);
      expect(
        state.progressByEpisode['b']!.percentBasis,
        NovelProgressPercentBasis.bodyGeometryV1,
      );
      expect(state.recentEpisodeId, 'b');
      expect(
        (await repository.getReadingProgress(novelId: 'novel'))!.episodeId,
        'b',
      );
      expect(
        (await shared.getWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel',
        ))!.lastReadEpisodeId,
        'b',
      );
    },
  );

  test(
    'malformed new fractions cannot replace a position, recent pointer or completion',
    () async {
      await repository.commitProgress(progress: position('a', 2));
      final oldRow = (await db.query(
        AppDatabase.novelReadingProgressTable,
      )).single;
      for (final fraction in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -.01,
        1.01,
      ]) {
        final malformed = NovelReadingProgress(
          novelId: 'novel',
          episodeId: 'b',
          scrollOffset: 900,
          updatedAt: DateTime(2026),
          progressPercent: fraction,
          isProgressPercentValid: true,
          percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        );
        expect(
          await repository.commitProgress(
            progress: malformed,
            markCompleted: true,
          ),
          false,
        );
        expect(
          (await db.query(AppDatabase.novelReadingProgressTable)).single,
          oldRow,
        );
        final state = await repository.loadWorkState(novelId: 'novel');
        expect(state.recentEpisodeId, 'a');
        expect(state.episodeStates, isEmpty);
      }
    },
  );

  test(
    'reading legacy opaque fraction data never rewrites or clamps the original row',
    () async {
      await db.insert(AppDatabase.novelReadingProgressTable, {
        'novel_id': 'novel',
        'episode_id': 'opaque',
        'scroll_offset': 12,
        'progress_percent': 1.25,
        'progress_percent_valid': null,
        'percent_basis': 'futureBasis',
        'updated_at': 123,
      });
      final before = (await db.query(
        AppDatabase.novelReadingProgressTable,
      )).single;
      final loaded = (await repository.getChapterProgress(
        novelId: 'novel',
        episodeId: 'opaque',
      ))!;
      expect(loaded.progressPercent, 1.25);
      expect(loaded.percentBasis, 'futureBasis');
      expect(
        (await repository.loadWorkState(
          novelId: 'novel',
        )).recentProgress!.progressPercent,
        1.25,
      );
      expect(
        (await db.query(AppDatabase.novelReadingProgressTable)).single,
        before,
      );
    },
  );

  test(
    'reset recent chapter falls back, retains bookmarks and other positions',
    () async {
      await repository.commitProgress(progress: position('a', 2));
      await repository.commitProgress(
        progress: position('b', 4),
        markCompleted: true,
      );
      await repository.toggleEpisodeBookmark(
        novelId: 'novel',
        episodeId: 'b',
        isBookmarked: true,
      );
      await repository.resetChapter(novelId: 'novel', episodeId: 'b');
      var state = await repository.loadWorkState(novelId: 'novel');
      expect(state.recentEpisodeId, 'a');
      expect(state.progressByEpisode.containsKey('b'), false);
      expect(state.episodeStates['b']!.isRead, false);
      expect(state.episodeStates['b']!.isBookmarked, true);
      await repository.resetChapter(novelId: 'novel', episodeId: 'a');
      state = await repository.loadWorkState(novelId: 'novel');
      expect(state.recentEpisodeId, isNull);
      expect(state.recentProgress, isNull);
      expect(
        (await shared.getWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel',
        ))!.lastReadEpisodeId,
        isNull,
      );
    },
  );

  test(
    'manual completion creates no position and legacy completion stays inert after bookmark update',
    () async {
      await db.insert(AppDatabase.libraryEpisodeStateTable, {
        'content_type': 'novel',
        'episode_id': 'old',
        'work_id': 'novel',
        'is_read': 1,
        'read_at': 123,
        'read_state_version': 0,
      });
      await repository.toggleEpisodeBookmark(
        novelId: 'novel',
        episodeId: 'old',
        isBookmarked: true,
      );
      var state = await repository.loadWorkState(novelId: 'novel');
      expect(state.episodeStates['old']!.isRead, false);
      expect(state.episodeStates['old']!.isBookmarked, true);
      final old = (await db.query(AppDatabase.libraryEpisodeStateTable)).single;
      expect(old['is_read'], 1);
      expect(old['read_at'], 123);
      expect(old['read_state_version'], 0);
      expect(
        await shared.countReadEpisodes(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel',
        ),
        0,
      );
      await repository.setChapterRead(
        novelId: 'novel',
        episodeId: 'new',
        isRead: true,
      );
      state = await repository.loadWorkState(novelId: 'novel');
      expect(state.episodeStates['new']!.isRead, true);
      expect(state.progressByEpisode, isEmpty);
      expect(state.recentEpisodeId, isNull);
    },
  );

  test(
    'retired guard before or after writes rolls back position, recent and completion',
    () async {
      await repository.commitProgress(progress: position('a', 2));
      expect(
        await repository.commitProgress(
          progress: position('b', 4),
          markCompleted: true,
          canCommit: () => false,
        ),
        false,
      );
      var calls = 0;
      expect(
        await repository.commitProgress(
          progress: position('b', 4),
          markCompleted: true,
          canCommit: () => ++calls == 1,
        ),
        false,
      );
      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.progressByEpisode.keys, ['a']);
      expect(state.recentEpisodeId, 'a');
      expect(state.episodeStates, isEmpty);
    },
  );

  test('database failure rolls back the full confirmed mutation', () async {
    await db.execute(
      '''CREATE TRIGGER fail_recent BEFORE INSERT ON library_work_state
      BEGIN SELECT RAISE(ABORT, 'controlled failure'); END''',
    );
    await expectLater(
      repository.commitProgress(
        progress: position('a', 2),
        markCompleted: true,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query(AppDatabase.novelReadingProgressTable), isEmpty);
    expect(await db.query(AppDatabase.libraryEpisodeStateTable), isEmpty);
  });

  test(
    'known-field writes preserve future position and shared metadata',
    () async {
      for (final table in [
        AppDatabase.novelReadingProgressTable,
        AppDatabase.libraryEpisodeStateTable,
        AppDatabase.libraryWorkStateTable,
      ]) {
        await db.execute('ALTER TABLE $table ADD COLUMN future_extension TEXT');
      }
      await repository.commitProgress(
        progress: position('a', 2),
        markCompleted: true,
      );
      for (final table in [
        AppDatabase.novelReadingProgressTable,
        AppDatabase.libraryEpisodeStateTable,
        AppDatabase.libraryWorkStateTable,
      ]) {
        await db.update(table, {'future_extension': 'opaque'});
      }
      await repository.commitProgress(progress: position('a', 3));
      await repository.toggleEpisodeBookmark(
        novelId: 'novel',
        episodeId: 'a',
        isBookmarked: true,
      );
      await shared.upsertWorkState(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel',
        introText: 'intro',
      );
      for (final table in [
        AppDatabase.novelReadingProgressTable,
        AppDatabase.libraryEpisodeStateTable,
        AppDatabase.libraryWorkStateTable,
      ]) {
        expect((await db.query(table)).single['future_extension'], 'opaque');
      }
      expect(
        (await repository.loadWorkState(
          novelId: 'novel',
        )).episodeStates['a']!.isRead,
        true,
      );
    },
  );

  test(
    'unknown percentage basis and unsupported anchor are opaque on round trip',
    () async {
      final future = NovelReadingProgress(
        novelId: 'novel',
        episodeId: 'future',
        scrollOffset: 9,
        updatedAt: DateTime(2026),
        percentBasis: 'futureBasis',
        progressPercent: .4,
        anchorFormatVersion: 99,
        anchorTextOffset: 1 << 35,
        anchorTextIdentity: ' future identity ',
        isProgressPercentValid: false,
      );
      await repository.commitProgress(progress: future);
      final loaded = (await repository.getChapterProgress(
        novelId: 'novel',
        episodeId: 'future',
      ))!;
      expect(loaded.percentBasis, 'futureBasis');
      expect(loaded.anchorFormatVersion, 99);
      expect(loaded.anchorTextOffset, 1 << 35);
      expect(loaded.anchorTextIdentity, ' future identity ');
      expect(loaded.isProgressPercentValid, false);
    },
  );

  test(
    'purge clears every chapter position and recent reference only for target work',
    () async {
      await repository.commitProgress(progress: position('a', 2));
      await repository.commitProgress(progress: position('b', 4));
      await repository.commitProgress(
        progress: NovelReadingProgress(
          novelId: 'other',
          episodeId: 'c',
          scrollOffset: 1,
          updatedAt: DateTime(2026),
        ),
      );
      await repository.purgeWork(novelId: 'novel');
      expect(
        (await repository.loadWorkState(novelId: 'novel')).progressByEpisode,
        isEmpty,
      );
      expect(
        (await shared.getWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel',
        ))!.lastReadEpisodeId,
        isNull,
      );
      expect(await repository.getReadingProgress(novelId: 'other'), isNotNull);
    },
  );
}
