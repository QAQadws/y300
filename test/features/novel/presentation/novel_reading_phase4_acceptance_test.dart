import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/models/novel_source_reading_context.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';
import 'package:y300/features/novel/presentation/adapters/novel_source_reading_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
    'two thousand chapter states use a single bounded SQLite read',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      const count = 2000;
      final batch = db.batch();
      for (var index = 0; index < count; index++) {
        batch.insert(AppDatabase.novelReadingProgressTable, {
          'novel_id': 'novel',
          'episode_id': 'chapter-$index',
          'scroll_offset': 0,
          'updated_at': index,
          'progress_percent': .42,
          'progress_percent_valid': 1,
          'percent_basis': NovelProgressPercentBasis.bodyGeometryV1,
        });
        batch.insert(AppDatabase.libraryEpisodeStateTable, {
          'content_type': 'novel',
          'work_id': 'novel',
          'episode_id': 'chapter-$index',
          'is_read': index.isEven ? 1 : 0,
          'read_state_version': 1,
          'is_bookmarked': index % 3 == 0 ? 1 : 0,
        });
      }
      batch.insert(AppDatabase.libraryWorkStateTable, {
        'content_type': 'novel',
        'work_id': 'novel',
        'last_read_episode_id': 'chapter-1999',
        'created_at': 0,
        'updated_at': 1999,
      });
      await batch.commit(noResult: true);
      final counted = _CountingDatabase(db);
      final catalog = _CatalogRepository(count);
      final adapter = NovelDetailAdapter(
        catalog,
        stateRepository: _UnusedLibraryStates(),
        readingStateRepository: SqfliteNovelReadingStateRepository(
          Future.value(counted),
        ),
      );
      final chapters = await adapter.loadChapters(
        workId: 'novel',
        filters: const LibraryFilterSet(),
        sortOption: LibraryChapterSortOption.defaults,
      );
      expect(chapters, hasLength(count));
      expect(
        chapters.where((chapter) => chapter.isRead),
        hasLength(count ~/ 2),
      );
      expect(chapters.where((chapter) => chapter.isBookmarked), hasLength(667));
      expect(chapters.last.progressInfo?.fraction, .42);
      expect(chapters.last.progressInfo?.isCurrent, true);
      expect(chapters.first.progressInfo?.isCurrent, false);
      expect(catalog.catalogReads, 1);
      expect(counted.transactions, 1);
      // Counting actual SQLite calls catches an N+1 regression independently of
      // wall-clock timings, which vary substantially between CI and devices.
      expect(counted.queries, 3);
    },
  );

  test('continuous source scrolling coalesces writes until a stable pause', () {
    fakeAsync((clock) {
      final source = _SourceHarness();
      unawaited(source.start());
      clock.flushMicrotasks();
      for (var frame = 1; frame <= 120; frame++) {
        source.report(frame, .8 * frame / 120);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 16));
        clock.flushMicrotasks();
      }
      expect(source.repository.writes, isEmpty);
      clock.elapse(const Duration(milliseconds: 183));
      clock.flushMicrotasks();
      expect(source.repository.writes, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      clock.flushMicrotasks();
      expect(source.repository.writes, hasLength(1));
      expect(
        source.repository.writes.single.progressPercent,
        closeTo(.8, 1e-9),
      );
      expect(source.notifications, 1);
      source.adapter.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'SQLite exit flush atomically saves only the latest scheduled sample',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final repository = _CountingSqliteCommits(
        SqfliteNovelReadingStateRepository(Future.value(db)),
      );
      final committer = DefaultNovelReaderProgressCommitter(
        repository: _CatalogRepository(0),
        readingStateRepository: repository,
        debounceDuration: const Duration(minutes: 1),
      );
      addTearDown(committer.cancel);
      final scope = Object();
      const snapshot = NovelReaderProgressSnapshot(
        novelId: 'novel',
        episodeId: 'chapter',
        flowMode: NovelReaderFlowMode.vertical,
        scrollOffset: 420,
        pageIndex: 0,
        progressPercent: .7,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
      );
      for (var frame = 1; frame <= 120; frame++) {
        committer.scheduleScoped(
          snapshot.copyWith(progressPercent: .7 * frame / 120),
          scope: scope,
          canCommit: () => true,
        );
      }
      expect(repository.commits, 0);
      expect(
        await committer.flushScoped(
          snapshot,
          scope: scope,
          canCommit: () => true,
        ),
        true,
      );
      expect(
        await committer.flushScoped(
          snapshot,
          scope: scope,
          canCommit: () => true,
        ),
        true,
      );
      final state = await repository.delegate.loadWorkState(novelId: 'novel');
      expect(repository.commits, 1);
      expect(state.progressByEpisode, hasLength(1));
      expect(state.progressByEpisode['chapter']!.progressPercent, .7);
      expect(state.recentEpisodeId, 'chapter');
      expect(state.episodeStates, isEmpty);
    },
  );

  test(
    'source exit flush saves the latest sample without waiting or a timer',
    () {
      fakeAsync((clock) {
        final source = _SourceHarness();
        unawaited(source.start());
        clock.flushMicrotasks();
        for (var frame = 1; frame <= 120; frame++) {
          source.report(frame, .7 * frame / 120);
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 1));
        }
        expect(source.repository.writes, isEmpty);
        // Match the route's admission-stop -> flush -> retire ordering.
        source.adapter.suspendForFlush();
        var finished = false;
        unawaited(source.adapter.flush().then((_) => finished = true));
        clock.flushMicrotasks();
        expect(finished, true);
        expect(source.repository.writes, hasLength(1));
        expect(
          source.repository.writes.single.progressPercent,
          closeTo(.7, 1e-9),
        );
        unawaited(source.adapter.flush());
        clock.flushMicrotasks();
        expect(source.repository.writes, hasLength(1));
        source.adapter.dispose();
        expect(clock.pendingTimers, isEmpty);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(source.repository.writes, hasLength(1));
      });
    },
  );
}

final class _CountingDatabase extends Fake implements Database {
  _CountingDatabase(this.delegate);
  final Database delegate;
  int transactions = 0;
  int queries = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    transactions++;
    return delegate.transaction(
      (txn) => action(_CountingTransaction(txn, () => queries++)),
      exclusive: exclusive,
    );
  }
}

final class _CountingTransaction extends Fake implements Transaction {
  _CountingTransaction(this.delegate, this.onQuery);
  final Transaction delegate;
  final void Function() onQuery;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    onQuery();
    return delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
}

final class _CatalogRepository extends Fake implements NovelRepository {
  _CatalogRepository(this.count);
  final int count;
  int catalogReads = 0;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    catalogReads++;
    return List.generate(
      count,
      (index) => NovelEpisodeItem(
        novelId: novelId,
        episodeId: 'chapter-$index',
        sourceTid: '100',
        sourcePid: '${index + 1000}',
        episodeTitle: 'Chapter $index',
        orderIndex: index,
      ),
    );
  }
}

final class _UnusedLibraryStates extends Fake
    implements LibraryStateRepository {}

final class _SourceHarness {
  _SourceHarness() {
    committer = DefaultNovelReaderProgressCommitter(repository: repository);
    adapter = NovelSourceReadingAdapter(
      context: NovelSourceReadingContext(
        novelId: 'novel',
        initialEpisodeId: 'chapter',
        chapters: const [
          NovelSourceReadingChapter(
            episodeId: 'chapter',
            sourceTid: '100',
            sourcePid: '101',
          ),
        ],
      ),
      readingStateRepository: repository,
      committer: committer,
      mutationBarrier: NovelReadingMutationBarrier(),
      onCommitted: () => notifications++,
    );
  }
  final repository = _CountingReadingRepository();
  late final DefaultNovelReaderProgressCommitter committer;
  late final NovelSourceReadingAdapter adapter;
  int notifications = 0;

  Future<void> start() async {
    await adapter.prepare();
    adapter.onContentChanged('page');
    adapter.onVisibility(frontmost: true, resumed: true);
  }

  void report(int revision, double fraction) => adapter.onViewport(
    ThreadBodyReadingViewport(
      contentIdentity: 'page',
      tid: '100',
      page: 1,
      idle: false,
      restoreSettled: true,
      userNavigationRevision: revision,
      samples: [
        ThreadBodyReadingSample(
          tid: '100',
          pid: '101',
          bodyIdentity: 'body',
          relativeBodyTop: -600 * fraction,
          bodyHeight: 1200,
          effectiveViewportHeight: 600,
          visibleExtent: 600,
          bodyReady: true,
          finalBoundaryKnown: true,
          geometryIdentity: 'layout',
        ),
      ],
    ),
  );
}

final class _CountingReadingRepository extends Fake
    implements NovelRepository, NovelReadingStateRepository {
  final List<NovelReadingProgress> writes = [];

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async => NovelReadingStateSnapshot(
    novelId: novelId,
    progressByEpisode: const {},
    episodeStates: const {},
  );

  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    if (canCommit?.call() == false) return false;
    writes.add(progress);
    return true;
  }
}

final class _CountingSqliteCommits extends Fake
    implements NovelReadingStateRepository {
  _CountingSqliteCommits(this.delegate);
  final NovelReadingStateRepository delegate;
  int commits = 0;

  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) {
    commits++;
    return delegate.commitProgress(
      progress: progress,
      markCompleted: markCompleted,
      canCommit: canCommit,
    );
  }
}
