import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';
import 'package:y300/features/novel/application/novel_reading_session_coordinator.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late LocalNovelRepository repository;
  late LocalLibraryStateRepository shared;
  late NovelReadingMutationBarrier barrier;
  late DefaultNovelReaderProgressCommitter committer;
  NovelSourceReadingAdapter? adapter;
  setUp(() async {
    db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    repository = LocalNovelRepository(Future.value(db));
    shared = LocalLibraryStateRepository(Future.value(db));
    barrier = NovelReadingMutationBarrier();
    committer = DefaultNovelReaderProgressCommitter(repository: repository);
  });
  tearDown(() async {
    adapter?.dispose();
    adapter = null;
    committer.cancel();
    await db.close();
  });

  Future<NovelSourceReadingAdapter> start({
    NovelReadingStateRepository? readingRepository,
    NovelReadingSessionCoordinator? coordinator,
  }) async {
    final value = adapter = NovelSourceReadingAdapter(
      context: NovelSourceReadingContext(
        novelId: 'novel',
        initialEpisodeId: 'a',
        chapters: const [
          NovelSourceReadingChapter(
            episodeId: 'a',
            sourceTid: '100',
            sourcePid: '101',
          ),
          NovelSourceReadingChapter(
            episodeId: 'b',
            sourceTid: '100',
            sourcePid: '102',
          ),
        ],
      ),
      readingStateRepository: readingRepository ?? repository,
      committer: committer,
      mutationBarrier: barrier,
      coordinator: coordinator,
      onCommitted: () {},
    );
    await value.prepare();
    value.onContentChanged('page');
    value.onVisibility(frontmost: true, resumed: true);
    return value;
  }

  test(
    'approximate source restore leaves old unknown metadata byte-for-byte intact',
    () async {
      await repository.commitProgress(progress: _old(.42));
      final before = (await db.query(
        AppDatabase.novelReadingProgressTable,
      )).single;
      final source = await start();
      final restore = source.restoreTarget(
        tid: '100',
        pid: '101',
        bodyIdentity: 'a',
      );
      expect(restore!.fraction, .42);
      source.onViewport(_viewport([_sample(top: -252)]));
      await source.flush();
      expect(
        (await db.query(AppDatabase.novelReadingProgressTable)).single,
        before,
      );
      expect(
        (await repository.loadWorkState(novelId: 'novel')).episodeStates,
        isEmpty,
      );
    },
  );

  test(
    'source updates the same row, invalidates reader auxiliaries and preserves flags',
    () async {
      await repository.commitProgress(progress: _old(.2));
      await shared.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel',
        episodeId: 'a',
        isBookmarked: true,
      );
      await repository.setChapterRead(
        novelId: 'novel',
        episodeId: 'a',
        isRead: true,
      );
      final source = await start();
      source.onViewport(_viewport([_sample(top: -360)], navigation: 1));
      await source.flush();
      final rows = await db.query(AppDatabase.novelReadingProgressTable);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['progress_percent'], .6);
      expect(row['percent_basis'], NovelProgressPercentBasis.bodyGeometryV1);
      expect(row['anchor_node_id'], isNull);
      expect(row['anchor_text_identity'], isNull);
      expect(row['anchor_format_version'], 0);
      expect(row['anchor_text_offset'], 0);
      expect(row['pagination_key'], isNull);
      expect(row['page_count'], isNull);
      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.episodeStates['a']!.isRead, true);
      expect(state.episodeStates['a']!.isBookmarked, true);
    },
  );

  test(
    'same-work chapters keep independent positions and atomic recent reference',
    () async {
      final source = await start();
      source.onViewport(_viewport([_sample(top: -180)], navigation: 1));
      await source.flush();
      source.onViewport(
        _viewport([_sample(pid: '102', top: -360)], navigation: 2),
      );
      await source.flush();
      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.progressByEpisode.keys, unorderedEquals(['a', 'b']));
      expect(state.progressByEpisode['a']!.progressPercent, .3);
      expect(state.progressByEpisode['b']!.progressPercent, .6);
      expect(state.recentEpisodeId, 'b');
    },
  );

  test(
    'queued underlying reader cannot overwrite newer source reading',
    () async {
      await repository.commitProgress(progress: _old(.1));
      final gate = _GatedRepository(repository);
      committer.cancel();
      committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
        readingStateRepository: gate,
      );
      final readerRevision = barrier.capture('novel', 'a');
      final readerSave = committer.flushScoped(
        _snapshot(.2),
        scope: Object(),
        canCommit: () => barrier.isCurrent('novel', 'a', readerRevision),
      );
      await gate.entered.future;
      final source = await start();
      source.onViewport(_viewport([_sample(top: -420)], navigation: 1));
      final sourceSave = source.flush();
      await Future<void>.value();
      gate.release.complete();
      expect(await readerSave, false);
      await sourceSave;
      final saved = (await repository.getChapterProgress(
        novelId: 'novel',
        episodeId: 'a',
      ))!;
      expect(saved.progressPercent, .7);
      expect(saved.anchorNodeId, isNull);
      expect(saved.percentBasis, NovelProgressPercentBasis.bodyGeometryV1);
    },
  );

  test(
    'manual reset retires an in-flight source position without losing bookmark',
    () async {
      await repository.commitProgress(progress: _old(.2));
      await shared.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel',
        episodeId: 'a',
        isBookmarked: true,
      );
      final gate = _GatedRepository(repository);
      committer.cancel();
      committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
        readingStateRepository: gate,
      );
      final source = await start();
      source.onViewport(_viewport([_sample(top: -360)], navigation: 1));
      final save = source.flush();
      await gate.entered.future;
      barrier.invalidate('novel', 'a');
      await repository.resetChapter(novelId: 'novel', episodeId: 'a');
      gate.release.complete();
      await save;
      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.progressByEpisode, isEmpty);
      expect(state.recentEpisodeId, isNull);
      expect(state.episodeStates['a']!.isRead, false);
      expect(state.episodeStates['a']!.isBookmarked, true);
    },
  );

  test('late atomic chapter-end confirmation cannot undo a reset', () async {
    final gate = _GatedRepository(repository);
    final source = await start(
      readingRepository: gate,
      coordinator: NovelReadingSessionCoordinator(
        completionStability: const Duration(milliseconds: 2),
      ),
    );
    source.onViewport(_viewport([_sample(height: 200, extent: 200)]));
    await gate.entered.future;
    expect(gate.completedWrite, true);
    barrier.invalidate('novel', 'a');
    await repository.resetChapter(novelId: 'novel', episodeId: 'a');
    gate.release.complete();
    await gate.finished.future;
    final state = await repository.loadWorkState(novelId: 'novel');
    expect(state.progressByEpisode, isEmpty);
    expect(state.recentEpisodeId, isNull);
    expect(state.episodeStates['a']!.isRead, false);
  });

  test(
    'work reset retires an in-flight first source save from another chapter',
    () async {
      await repository.commitProgress(progress: _old(.2), markCompleted: true);
      await shared.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel',
        episodeId: 'a',
        isBookmarked: true,
      );
      final gate = _GatedRepository(repository);
      committer.cancel();
      committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
        readingStateRepository: gate,
      );
      final source = await start();
      source.onViewport(
        _viewport([_sample(pid: '102', top: -360)], navigation: 1),
      );
      final save = source.flush();
      await gate.entered.future;
      final detail = NovelDetailAdapter(
        repository,
        stateRepository: shared,
        mutationBarrier: barrier,
      );

      await detail.resetWorkReadingState(workId: 'novel');
      gate.release.complete();
      await save;

      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.progressByEpisode, isEmpty);
      expect(state.recentEpisodeId, isNull);
      expect(state.episodeStates['a']!.isRead, isFalse);
      expect(state.episodeStates['a']!.isBookmarked, isTrue);
      expect(state.episodeStates.containsKey('b'), isFalse);
      await source.flush();
      expect(
        (await repository.loadWorkState(novelId: 'novel')).progressByEpisode,
        isEmpty,
      );
    },
  );

  test(
    'work reset rejects late source completion before the first chapter row',
    () async {
      final gate = _GatedRepository(repository);
      final source = await start(
        readingRepository: gate,
        coordinator: NovelReadingSessionCoordinator(
          completionStability: const Duration(milliseconds: 2),
        ),
      );
      source.onViewport(_viewport([_sample(height: 200, extent: 200)]));
      await gate.entered.future;
      expect(gate.completedWrite, isTrue);
      final detail = NovelDetailAdapter(
        repository,
        stateRepository: shared,
        mutationBarrier: barrier,
      );

      await detail.resetWorkReadingState(workId: 'novel');
      gate.release.complete();
      await gate.finished.future;

      final state = await repository.loadWorkState(novelId: 'novel');
      expect(state.progressByEpisode, isEmpty);
      expect(state.recentEpisodeId, isNull);
      expect(state.episodeStates, isEmpty);
    },
  );
}

NovelReadingProgress _old(double fraction) => NovelReadingProgress(
  novelId: 'novel',
  episodeId: 'a',
  scrollOffset: 900,
  updatedAt: DateTime(2026),
  flowMode: NovelReaderFlowMode.pagedLtr,
  pageIndex: 5,
  pageCount: 11,
  anchorNodeId: 'legacy',
  anchorTextOffset: -17,
  anchorFormatVersion: 72,
  anchorTextIdentity: 'future-text',
  paginationKey: 'old-layout',
  progressPercent: fraction,
  isProgressPercentValid: true,
  percentBasis: 'future',
);

NovelReaderProgressSnapshot _snapshot(double fraction) =>
    NovelReaderProgressSnapshot(
      novelId: 'novel',
      episodeId: 'a',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 2,
      pageCount: 10,
      progressPercent: fraction,
      isProgressPercentValid: true,
      percentBasis: NovelProgressPercentBasis.pagedStartV1,
    );

ThreadBodyReadingSample _sample({
  String pid = '101',
  double top = 0,
  double height = 1200,
  double extent = 600,
}) => ThreadBodyReadingSample(
  tid: '100',
  pid: pid,
  bodyIdentity: pid,
  relativeBodyTop: top,
  bodyHeight: height,
  effectiveViewportHeight: 600,
  visibleExtent: extent,
  bodyReady: true,
  finalBoundaryKnown: true,
  geometryIdentity: (pid, height),
);

ThreadBodyReadingViewport _viewport(
  List<ThreadBodyReadingSample> samples, {
  int navigation = 0,
}) => ThreadBodyReadingViewport(
  contentIdentity: 'page',
  tid: '100',
  page: 1,
  samples: samples,
  idle: true,
  restoreSettled: true,
  userNavigationRevision: navigation,
);

final class _GatedRepository implements NovelReadingStateRepository {
  _GatedRepository(this.delegate);
  final NovelReadingStateRepository delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();
  bool completedWrite = false;
  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    if (!entered.isCompleted) {
      completedWrite = markCompleted;
      entered.complete();
      await release.future;
    }
    final applied = await delegate.commitProgress(
      progress: progress,
      markCompleted: markCompleted,
      canCommit: canCommit,
    );
    if (!finished.isCompleted) finished.complete();
    return applied;
  }

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({required String novelId}) =>
      delegate.loadWorkState(novelId: novelId);
  @override
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  }) => delegate.getChapterProgress(novelId: novelId, episodeId: episodeId);
  @override
  Future<bool> resetChapter({
    required String novelId,
    required String episodeId,
    bool Function()? canCommit,
  }) => delegate.resetChapter(
    novelId: novelId,
    episodeId: episodeId,
    canCommit: canCommit,
  );
  @override
  Future<bool> setChapterRead({
    required String novelId,
    required String episodeId,
    required bool isRead,
    bool Function()? canCommit,
  }) => delegate.setChapterRead(
    novelId: novelId,
    episodeId: episodeId,
    isRead: isRead,
    canCommit: canCommit,
  );
}
