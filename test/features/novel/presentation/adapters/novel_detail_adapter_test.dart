import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';

void main() {
  test(
    'NovelDetailAdapter exposes chapter read-state and work reset capabilities',
    () {
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        stateRepository: _RecordingLibraryStateRepository(),
      );

      expect(adapter, isA<DetailChapterReadStateAdapter>());
      expect(adapter, isA<DetailWorkReadingResetAdapter>());
    },
  );

  test(
    'loadChapters reads one snapshot for all chapter positions and states',
    () async {
      final states = _RecordingLibraryStateRepository();
      final reading = _FakeNovelReadingStateRepository(
        recentEpisodeId: 'novel:1:2',
        progressByEpisode: {
          'novel:1:1': _chapterPosition('novel:1:1', 0.2),
          'novel:1:2': _chapterPosition('novel:1:2', 0.42),
        },
        episodeStates: const {
          'novel:1:1': LibraryEpisodeState(
            moduleKey: LibraryModuleKey.novel,
            episodeId: 'novel:1:1',
            workId: 'novel:1',
            isRead: true,
            isBookmarked: true,
          ),
        },
      );
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        stateRepository: states,
        readingStateRepository: reading,
      );
      final chapters = await adapter.loadChapters(
        workId: 'novel:1',
        filters: const LibraryFilterSet(),
        sortOption: LibraryChapterSortOption.defaults,
      );
      final first = chapters.singleWhere(
        (item) => item.episodeId == 'novel:1:1',
      );
      final recent = chapters.singleWhere(
        (item) => item.episodeId == 'novel:1:2',
      );
      expect(first.isRead, isTrue);
      expect(first.isBookmarked, isTrue);
      expect(first.progressInfo?.fraction, 0.2);
      expect(first.progressInfo?.isCurrent, isFalse);
      expect(recent.progressInfo?.fraction, 0.42);
      expect(recent.progressInfo?.isCurrent, isTrue);
      expect(reading.snapshotReads, 1);
      expect(states.episodeStateReads, 0);

      final unread = await adapter.loadChapters(
        workId: 'novel:1',
        filters: const LibraryFilterSet(unread: TriStateFilterValue.include),
        sortOption: LibraryChapterSortOption.defaults,
      );
      expect(unread.single.episodeId, 'novel:1:2');
    },
  );

  test(
    'continue advances a completed recent chapter and retains the final chapter',
    () async {
      for (final sample in [
        ('novel:1:1', 'novel:1:2'),
        ('novel:1:2', 'novel:1:2'),
      ]) {
        final adapter = NovelDetailAdapter(
          _FakeNovelRepository(),
          stateRepository: _RecordingLibraryStateRepository(),
          readingStateRepository: _FakeNovelReadingStateRepository(
            recentEpisodeId: sample.$1,
            episodeStates: {
              sample.$1: LibraryEpisodeState(
                moduleKey: LibraryModuleKey.novel,
                episodeId: sample.$1,
                workId: 'novel:1',
                isRead: true,
              ),
            },
          ),
        );
        expect(
          (await adapter.getReaderRouteTarget(
            workId: 'novel:1',
            preferContinue: true,
          ))?.episodeId,
          sample.$2,
        );
      }
    },
  );

  test(
    'read mutations invalidate pending producers and delegate atomic reset',
    () async {
      final reading = _FakeNovelReadingStateRepository();
      final barrier = NovelReadingMutationBarrier();
      final revision = barrier.capture('novel:1', 'novel:1:1');
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        stateRepository: _RecordingLibraryStateRepository(),
        readingStateRepository: reading,
        mutationBarrier: barrier,
      );
      await adapter.markChapterRead(
        workId: 'novel:1',
        episodeId: 'novel:1:1',
        isRead: true,
      );
      expect(barrier.isCurrent('novel:1', 'novel:1:1', revision), isFalse);
      expect(reading.readMutations, [('novel:1', 'novel:1:1', true)]);
      await adapter.resetChapterReadingState(
        workId: 'novel:1',
        episodeId: 'novel:1:1',
      );
      expect(reading.resetEpisodeIds, ['novel:1:1']);
      reading.appliesMutation = false;
      await expectLater(
        adapter.markChapterRead(
          workId: 'novel:1',
          episodeId: 'novel:1:1',
          isRead: true,
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  for (final reset in [false, true]) {
    test(
      'a queued ${reset ? 'reset' : 'completion mark'} cannot override newer navigation',
      () async {
        final release = Completer<void>();
        final reading = _FakeNovelReadingStateRepository()
          ..beforeMutation = release.future;
        final barrier = NovelReadingMutationBarrier();
        final adapter = NovelDetailAdapter(
          _FakeNovelRepository(),
          stateRepository: _RecordingLibraryStateRepository(),
          readingStateRepository: reading,
          mutationBarrier: barrier,
        );
        final pending = reset
            ? adapter.resetChapterReadingState(
                workId: 'novel:1',
                episodeId: 'novel:1:1',
              )
            : adapter.markChapterRead(
                workId: 'novel:1',
                episodeId: 'novel:1:1',
                isRead: true,
              );
        // A frontmost reader's real navigation takes newer authority while the
        // older detail action is still waiting for the persistence transaction.
        barrier.invalidate('novel:1', 'novel:1:1');
        release.complete();
        await pending;
        expect(reading.committedMutations, 0);
      },
    );
  }

  test('work reset delegates once and retires every older producer', () async {
    final reading = _FakeNovelReadingStateRepository();
    final barrier = NovelReadingMutationBarrier();
    final persisted = barrier.capture('novel:1', 'novel:1:1');
    final pending = barrier.capture('novel:1', 'not-yet-persisted');
    final other = barrier.capture('novel:2', 'novel:2:1');
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(),
      stateRepository: _RecordingLibraryStateRepository(),
      readingStateRepository: reading,
      mutationBarrier: barrier,
    );

    await adapter.resetWorkReadingState(workId: 'novel:1');

    expect(reading.resetWorkIds, ['novel:1']);
    expect(reading.resetEpisodeIds, isEmpty);
    expect(reading.committedMutations, 1);
    expect(barrier.isCurrent('novel:1', 'novel:1:1', persisted), isFalse);
    expect(barrier.isCurrent('novel:1', 'not-yet-persisted', pending), isFalse);
    expect(barrier.isCurrent('novel:2', 'novel:2:1', other), isTrue);
    reading.appliesMutation = false;
    await expectLater(
      adapter.resetWorkReadingState(workId: 'novel:1'),
      throwsA(isA<Exception>()),
    );
  });

  test('new navigation in any chapter retires a queued work reset', () async {
    final release = Completer<void>();
    final reading = _FakeNovelReadingStateRepository()
      ..beforeMutation = release.future;
    final barrier = NovelReadingMutationBarrier();
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(),
      stateRepository: _RecordingLibraryStateRepository(),
      readingStateRepository: reading,
      mutationBarrier: barrier,
    );
    final pending = adapter.resetWorkReadingState(workId: 'novel:1');
    barrier.invalidate('novel:1', 'newly-discovered-chapter');
    release.complete();
    await pending;
    expect(reading.resetWorkIds, ['novel:1']);
    expect(reading.committedMutations, 0);
  });

  test('unsupported work reset preserves producer revisions', () async {
    final barrier = NovelReadingMutationBarrier();
    final revision = barrier.capture('novel:1', 'novel:1:1');
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(),
      stateRepository: _RecordingLibraryStateRepository(),
      mutationBarrier: barrier,
    );
    await expectLater(
      adapter.resetWorkReadingState(workId: 'novel:1'),
      throwsA(isA<Exception>()),
    );
    expect(barrier.isCurrent('novel:1', 'novel:1:1', revision), isTrue);
  });

  test('loadChapters sorts novel sources by numeric pid', () async {
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(),
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final ascending = await adapter.loadChapters(
      workId: 'novel:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );
    final descending = await adapter.loadChapters(
      workId: 'novel:1',
      filters: const LibraryFilterSet(),
      sortOption: const LibraryChapterSortOption(
        direction: LibrarySortDirection.desc,
      ),
    );

    expect(ascending.map((chapter) => chapter.sourcePid), <String?>['2', '10']);
    expect(descending.map((chapter) => chapter.sourcePid), <String?>[
      '10',
      '2',
    ]);
  });

  test('loadChapters maps paged novel progress to percentage', () async {
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'novel:1:2',
          scrollOffset: 0,
          updatedAt: DateTime(2026, 6, 9),
          flowMode: NovelReaderFlowMode.pagedLtr,
          pageIndex: 2,
          progressPercent: 0.35,
        ),
      ),
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final chapters = await adapter.loadChapters(
      workId: 'novel:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );
    final current = chapters.singleWhere(
      (chapter) => chapter.episodeId == 'novel:1:2',
    );

    expect(current.progressInfo?.kind, LibraryChapterProgressKind.percentage);
    expect(current.progressInfo?.fraction, 0.35);
    expect(current.progressInfo?.isCurrent, isTrue);
  });

  test('loadChapters marks the latest vertical chapter as last read', () async {
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'novel:1:1',
          scrollOffset: 120,
          updatedAt: DateTime(2026, 6, 9),
          progressPercent: 0.42,
        ),
      ),
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final chapters = await adapter.loadChapters(
      workId: 'novel:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );
    final current = chapters.singleWhere(
      (chapter) => chapter.episodeId == 'novel:1:1',
    );

    expect(current.progressInfo?.kind, LibraryChapterProgressKind.percentage);
    expect(current.progressInfo?.fraction, 0.42);
    expect(current.progressInfo?.isCurrent, isTrue);
    expect(
      chapters
          .singleWhere((chapter) => chapter.episodeId == 'novel:1:2')
          .progressInfo,
      isNull,
    );
  });

  test(
    'hidden source identifiers remain available for sorting and routing',
    () async {
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        stateRepository: _RecordingLibraryStateRepository(),
      );

      final chapters = await adapter.loadChapters(
        workId: 'novel:1',
        filters: const LibraryFilterSet(),
        sortOption: LibraryChapterSortOption.defaults,
      );

      expect(chapters.map((chapter) => chapter.sourcePid), <String?>[
        '2',
        '10',
      ]);
      expect(chapters.every((chapter) => chapter.sourceTid == '100'), isTrue);
      expect(
        chapters.every((chapter) => !chapter.showSourceIdentifier),
        isTrue,
      );
      expect(chapters.map((chapter) => chapter.title), <String>['第二章', '第一章']);
    },
  );

  for (final sample in <({String name, double fraction, bool? valid})>[
    (name: 'legacy zero', fraction: 0, valid: null),
    (name: 'explicitly invalid partial progress', fraction: 0.42, valid: false),
    (name: 'non-finite progress', fraction: double.nan, valid: true),
    (name: 'negative progress', fraction: -0.1, valid: true),
    (name: 'out-of-range progress', fraction: 1.1, valid: true),
  ]) {
    test(
      'loadChapters keeps ${sample.name} as a last-read marker only',
      () async {
        final adapter = NovelDetailAdapter(
          _FakeNovelRepository(
            progress: NovelReadingProgress(
              novelId: 'novel:1',
              episodeId: 'novel:1:1',
              scrollOffset: 120,
              updatedAt: DateTime(2026, 10, 7),
              progressPercent: sample.fraction,
              isProgressPercentValid: sample.valid,
            ),
          ),
          stateRepository: _RecordingLibraryStateRepository(),
        );

        final chapters = await adapter.loadChapters(
          workId: 'novel:1',
          filters: const LibraryFilterSet(),
          sortOption: LibraryChapterSortOption.defaults,
        );
        final current = chapters.singleWhere(
          (chapter) => chapter.episodeId == 'novel:1:1',
        );

        expect(
          current.progressInfo?.kind,
          LibraryChapterProgressKind.percentage,
        );
        expect(current.progressInfo?.fraction, isNull);
        expect(current.progressInfo?.isCurrent, isTrue);
        expect(current.isRead, isFalse);
      },
    );
  }

  test(
    'loadChapters displays explicitly valid zero without marking completion',
    () async {
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(
          progress: NovelReadingProgress(
            novelId: 'novel:1',
            episodeId: 'novel:1:1',
            scrollOffset: 0,
            updatedAt: DateTime(2026, 10, 7),
            progressPercent: 0,
            isProgressPercentValid: true,
          ),
        ),
        stateRepository: _RecordingLibraryStateRepository(),
      );

      final chapters = await adapter.loadChapters(
        workId: 'novel:1',
        filters: const LibraryFilterSet(),
        sortOption: LibraryChapterSortOption.defaults,
      );
      final current = chapters.singleWhere(
        (chapter) => chapter.episodeId == 'novel:1:1',
      );

      expect(current.progressInfo?.kind, LibraryChapterProgressKind.percentage);
      expect(current.progressInfo?.fraction, 0);
      expect(current.isRead, isFalse);
    },
  );

  for (final identity in <({String name, String novelId, String episodeId})>[
    (name: 'another work', novelId: 'novel:2', episodeId: 'novel:1:1'),
    (name: 'missing chapter', novelId: 'novel:1', episodeId: 'removed:chapter'),
  ]) {
    test(
      'loadChapters ignores a saved position for ${identity.name}',
      () async {
        final adapter = NovelDetailAdapter(
          _FakeNovelRepository(
            progress: NovelReadingProgress(
              novelId: identity.novelId,
              episodeId: identity.episodeId,
              scrollOffset: 120,
              updatedAt: DateTime(2026, 10, 7),
              progressPercent: 0.42,
              isProgressPercentValid: true,
            ),
          ),
          stateRepository: _RecordingLibraryStateRepository(),
        );

        final chapters = await adapter.loadChapters(
          workId: 'novel:1',
          filters: const LibraryFilterSet(),
          sortOption: LibraryChapterSortOption.defaults,
        );

        expect(
          chapters.every((chapter) => chapter.progressInfo == null),
          isTrue,
        );
      },
    );
  }

  test(
    'loadChapters keeps last-read marker independent from read completion',
    () async {
      final progress = NovelReadingProgress(
        novelId: 'novel:1',
        episodeId: 'novel:1:1',
        scrollOffset: 120,
        updatedAt: DateTime(2026, 6, 9),
      );
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(progress: progress),
        stateRepository: _RecordingLibraryStateRepository(),
      );

      final chapters = await adapter.loadChapters(
        workId: 'novel:1',
        filters: const LibraryFilterSet(),
        sortOption: LibraryChapterSortOption.defaults,
      );

      expect(
        chapters
            .singleWhere((chapter) => chapter.episodeId == 'novel:1:1')
            .progressInfo
            ?.kind,
        LibraryChapterProgressKind.percentage,
      );

      final readAdapter = NovelDetailAdapter(
        _FakeNovelRepository(progress: progress),
        stateRepository: _RecordingLibraryStateRepository(
          episodeStates: <String, LibraryEpisodeState>{
            'novel:1:1': const LibraryEpisodeState(
              moduleKey: LibraryModuleKey.novel,
              episodeId: 'novel:1:1',
              workId: 'novel:1',
              isRead: true,
            ),
          },
        ),
      );
      final readChapters = await readAdapter.loadChapters(
        workId: 'novel:1',
        filters: const LibraryFilterSet(),
        sortOption: LibraryChapterSortOption.defaults,
      );

      expect(
        readChapters
            .singleWhere((chapter) => chapter.episodeId == 'novel:1:1')
            .progressInfo
            ?.kind,
        LibraryChapterProgressKind.percentage,
      );
      expect(
        readChapters
            .singleWhere((chapter) => chapter.episodeId == 'novel:1:1')
            .isRead,
        isFalse,
      );
    },
  );

  test('refreshWork delegates to the shared chapter update service', () async {
    final repository = _FakeNovelRepository();
    final updateService = _RecordingNovelChapterUpdateService();
    final adapter = NovelDetailAdapter(
      repository,
      stateRepository: _RecordingLibraryStateRepository(),
      chapterUpdateServiceFactory: () => updateService,
    );

    final result = await adapter.refreshWork(workId: 'novel:1');
    final fullResult = await adapter.refreshWorkFully(workId: 'novel:1');

    expect(updateService.novelIds, <String>['novel:1', 'novel:1']);
    expect(updateService.intents, <NovelChapterUpdateIntent>[
      NovelChapterUpdateIntent.normal,
      NovelChapterUpdateIntent.full,
    ]);
    expect(result.status, DetailRefreshStatus.immediate);
    expect(result.outcomeCode, DetailRefreshOutcomeCode.chaptersChanged);
    expect(result.insertedCount, 1);
    expect(result.updatedCount, 2);
    expect(fullResult.outcomeCode, DetailRefreshOutcomeCode.chaptersChanged);
  });

  test('loadHeader exposes source asset without synchronous caching', () async {
    final repository = _FakeNovelRepositoryWithCoverWriter(
      coverImageUrl: 'https://img.test/novel-cover.jpg',
    );
    final adapter = NovelDetailAdapter(
      repository,
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'novel:1');

    expect(header.coverLocalPath, isNull);
    expect(header.coverAsset?.assetId, 'novel/novel:1/source');
    expect(header.coverAsset?.kind, LibraryCoverAssetKind.source);
    expect(header.coverAsset?.sourceUrl, 'https://img.test/novel-cover.jpg');
    expect(header.sourceTitle, 'Novel');
    expect(header.sourceAuthor, isNull);
    expect(header.publisherName, 'Novel Author');
    expect(repository.lastCoverImageUrl, isNull);
    expect(repository.lastCoverLocalPath, isNull);
  });

  test(
    'loadHeader exposes publisher name and source intro without UID',
    () async {
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        stateRepository: _RecordingLibraryStateRepository(),
        sourceStateRepository: _FakeNovelSourceStateRepository(
          NovelSourceState(
            novelId: 'novel:1',
            publisherId: '406769',
            publisherName: 'Novel Author',
            firstPostPid: '5001',
            sourceIntro: '来源简介',
            catalogEntries: const <NovelSourceCatalogEntry>[],
            metadataSourceVersion: 4,
            hydrationState: NovelChapterHydrationState.metadataOnly,
            metadataIngestedAt: DateTime(2026, 7, 13),
            chaptersHydratedAt: null,
            lastCompletedAuthorPage: 0,
            lastSeenPid: null,
            lastSyncAt: null,
            lastError: null,
          ),
        ),
      );

      final header = await adapter.loadHeader(workId: 'novel:1');

      expect(header.publisherName, 'Novel Author');
      expect(header.publisherId, isNull);
      expect(header.intro, '来源简介');
    },
  );

  test('loadHeader keeps custom title cover and publisher', () async {
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(
        customTitle: '自定义标题',
        customCoverLocalPath: 'cache/custom-cover.jpg',
        customCoverFocusX: 0.2,
        customCoverFocusY: -0.4,
      ),
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'novel:1');

    expect(header.title, '自定义标题');
    expect(header.author, isNull);
    expect(header.translationGroup, isNull);
    expect(header.publisherName, 'Novel Author');
    expect(header.sourceAuthor, isNull);
    expect(header.customCoverLocalPath, 'cache/custom-cover.jpg');
    expect(header.customCoverFocusX, 0.2);
    expect(header.customCoverFocusY, -0.4);
  });

  test('loadHeader hides persisted source cover after cancellation', () async {
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(
        coverImageUrl: 'https://img.test/source-cover.jpg',
        customCoverLocalPath: 'cache/custom-cover.jpg',
        coverHidden: true,
      ),
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'novel:1');

    expect(header.coverImageUrl, isNull);
    expect(header.coverLocalPath, isNull);
    expect(header.customCoverLocalPath, isNull);
    expect(adapter.canRemoveCover(header), isFalse);
  });

  test('source cover can be cancelled without a custom cover', () async {
    final adapter = NovelDetailAdapter(
      _FakeNovelRepository(coverImageUrl: 'https://img.test/source-cover.jpg'),
      stateRepository: _RecordingLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'novel:1');

    expect(adapter.canRemoveCover(header), isTrue);
  });

  test(
    'metadata and custom cover mutations delegate to novel capabilities',
    () async {
      final repository = _EditableNovelRepository();
      final coverStore = _RecordingLibraryCoverStore();
      final adapter = NovelDetailAdapter(
        repository,
        coverStore: coverStore,
        stateRepository: _RecordingLibraryStateRepository(),
      );

      await adapter.updateCustomMetadata(
        workId: 'novel:1',
        customTitle: '标题',
        customSearchTitle: 'ignored',
      );
      await adapter.setCustomCoverFromLocalFile(
        workId: 'novel:1',
        sourceLocalPath: '/picked/source.jpg',
        focusX: 0.4,
        focusY: -0.2,
      );
      await adapter.updateCustomCoverFocus(
        workId: 'novel:1',
        focusX: -0.1,
        focusY: 0.3,
      );
      await adapter.removeCustomCover(workId: 'novel:1');

      expect(repository.lastCustomTitle, '标题');
      expect(coverStore.installedSourcePath, '/picked/source.jpg');
      expect(coverStore.installedAsset?.assetId, 'novel/novel:1/custom');
      expect(coverStore.installedAsset?.revision, 1);
      expect(repository.activatedRevision, 1);
      expect(repository.lastFocusX, -0.1);
      expect(repository.lastFocusY, 0.3);
      expect(repository.coverRemoved, isTrue);
    },
  );
}

class _FakeNovelSourceStateRepository implements NovelSourceStateRepository {
  const _FakeNovelSourceStateRepository(this.state);

  final NovelSourceState? state;

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    return state;
  }

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {}

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {}

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {}
}

class _RecordingNovelChapterUpdateService implements NovelChapterUpdateService {
  final List<String> novelIds = <String>[];
  final List<NovelChapterUpdateIntent> intents = <NovelChapterUpdateIntent>[];

  @override
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  }) async {
    novelIds.add(novelId);
    intents.add(intent);
    return NovelChapterSyncResult(
      mode: NovelChapterSyncMode.incremental,
      fetchedPages: 1,
      insertedCount: 1,
      updatedCount: 2,
      totalCount: 3,
      checkpoint: NovelChapterSyncCheckpoint(
        novelId: novelId,
        publisherId: '406769',
        lastCompletedAuthorPage: 3,
        lastSeenPid: '2',
        completedAt: DateTime(2026, 7, 14),
      ),
    );
  }
}

class _FakeNovelRepository implements NovelRepository {
  _FakeNovelRepository({
    this.progress,
    this.coverImageUrl,
    this.customTitle,
    this.customCoverLocalPath,
    this.customCoverFocusX,
    this.customCoverFocusY,
    this.coverHidden = false,
  });

  final NovelReadingProgress? progress;
  final String? coverImageUrl;
  final String? customTitle;
  final String? customCoverLocalPath;
  final double? customCoverFocusX;
  final double? customCoverFocusY;
  final bool coverHidden;

  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => null;

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '75',
      title: 'Novel',
      author: 'Novel Author',
      customTitle: customTitle,
      coverImageUrl: coverImageUrl,
      customCoverLocalPath: customCoverLocalPath,
      customCoverFocusX: customCoverFocusX,
      customCoverFocusY: customCoverFocusY,
      coverHidden: coverHidden,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 2,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return <NovelEpisodeItem>[
      NovelEpisodeItem(
        episodeId: '$novelId:1',
        novelId: novelId,
        sourceTid: '100',
        sourcePid: '10',
        episodeTitle: '第一章',
        orderIndex: 10,
      ),
      NovelEpisodeItem(
        episodeId: '$novelId:2',
        novelId: novelId,
        sourceTid: '100',
        sourcePid: '2',
        episodeTitle: '第二章',
        orderIndex: 0,
      ),
    ];
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async => progress;

  @override
  Future<List<NovelItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const <NovelItem>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    int anchorFormatVersion = 0,
    String? anchorTextIdentity,
    bool? isProgressPercentValid,
    String? paginationKey,
    double progressPercent = 0,
  }) async {}

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {}

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return const <NovelReaderBookmark>[];
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {}

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}
}

class _FakeNovelRepositoryWithCoverWriter extends _FakeNovelRepository
    implements NovelCoverCacheWriter {
  _FakeNovelRepositoryWithCoverWriter({super.coverImageUrl});

  String? lastCoverImageUrl;
  String? lastCoverLocalPath;
  String? lastCustomCoverLocalPath;

  @override
  Future<void> updateCoverCache({
    required String novelId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCoverImageUrl = coverImageUrl;
    lastCoverLocalPath = coverLocalPath;
    lastCustomCoverLocalPath = customCoverLocalPath;
  }
}

class _EditableNovelRepository extends _FakeNovelRepository
    implements
        NovelCustomMetadataWriter,
        NovelCustomCoverWriter,
        NovelCustomCoverAssetWriter {
  String? lastCustomTitle;
  String? lastCustomCoverPath;
  double? lastFocusX;
  double? lastFocusY;
  bool coverRemoved = false;
  int? activatedRevision;

  @override
  Future<void> activateCustomCoverAsset({
    required String novelId,
    required int revision,
    double? focusX,
    double? focusY,
  }) async {
    activatedRevision = revision;
    lastFocusX = focusX;
    lastFocusY = focusY;
  }

  @override
  Future<void> updateCustomMetadata({
    required String novelId,
    String? customTitle,
  }) async {
    lastCustomTitle = customTitle;
  }

  @override
  Future<void> updateCustomCover({
    required String novelId,
    required String customCoverLocalPath,
    double? focusX,
    double? focusY,
  }) async {
    lastCustomCoverPath = customCoverLocalPath;
    lastFocusX = focusX;
    lastFocusY = focusY;
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String novelId,
    double? focusX,
    double? focusY,
  }) async {
    lastFocusX = focusX;
    lastFocusY = focusY;
  }

  @override
  Future<void> removeCustomCover({required String novelId}) async {
    coverRemoved = true;
  }
}

class _RecordingLibraryCoverStore implements LibraryCoverStore {
  LibraryCoverAssetRef? installedAsset;
  String? installedSourcePath;
  String? deletedAssetId;
  LibraryCoverAssetRef? reclaimedAsset;

  @override
  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  }) async {
    installedAsset = asset;
    installedSourcePath = sourcePath;
  }

  @override
  Future<void> deleteAsset(String assetId) async {
    deletedAssetId = assetId;
  }

  @override
  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset) async {
    reclaimedAsset = asset;
  }

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingLibraryStateRepository implements LibraryStateRepository {
  _RecordingLibraryStateRepository({
    this.episodeStates = const <String, LibraryEpisodeState>{},
  });

  final Map<String, LibraryEpisodeState> episodeStates;
  int episodeStateReads = 0;
  LibraryWorkState? workState;

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<String> createTag({required String name}) async => 'tag-1';

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    episodeStateReads++;
    return episodeStates[episodeId];
  }

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => workState;

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => const <LibraryTag>[];

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => false;

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {}

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {
    final previous = workState;
    workState = LibraryWorkState(
      moduleKey: moduleKey,
      workId: workId,
      lastReadEpisodeId: lastReadEpisodeId ?? previous?.lastReadEpisodeId,
      lastReadAt: lastReadAt ?? previous?.lastReadAt,
      checkUpdatedAt: checkUpdatedAt ?? previous?.checkUpdatedAt,
      fetchedUpdatedAt: fetchedUpdatedAt ?? previous?.fetchedUpdatedAt,
      introText: introText ?? previous?.introText,
      createdAt: previous?.createdAt ?? DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }
}

NovelReadingProgress _chapterPosition(String episodeId, double percent) =>
    NovelReadingProgress(
      novelId: 'novel:1',
      episodeId: episodeId,
      scrollOffset: 80,
      progressPercent: percent,
      isProgressPercentValid: true,
      updatedAt: DateTime(2026, 10, 7),
    );

class _FakeNovelReadingStateRepository
    implements NovelReadingStateRepository, NovelWorkReadingResetRepository {
  _FakeNovelReadingStateRepository({
    this.progressByEpisode = const {},
    this.episodeStates = const {},
    this.recentEpisodeId,
  });
  final Map<String, NovelReadingProgress> progressByEpisode;
  final Map<String, LibraryEpisodeState> episodeStates;
  final String? recentEpisodeId;
  int snapshotReads = 0;
  bool appliesMutation = true;
  Future<void>? beforeMutation;
  int committedMutations = 0;
  final readMutations = <(String, String, bool)>[];
  final resetEpisodeIds = <String>[];
  final resetWorkIds = <String>[];

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async {
    snapshotReads++;
    return NovelReadingStateSnapshot(
      novelId: novelId,
      progressByEpisode: progressByEpisode,
      episodeStates: episodeStates,
      recentEpisodeId: recentEpisodeId,
    );
  }

  @override
  Future<bool> setChapterRead({
    required String novelId,
    required String episodeId,
    required bool isRead,
    bool Function()? canCommit,
  }) async {
    readMutations.add((novelId, episodeId, isRead));
    await beforeMutation;
    if (canCommit?.call() == false) return false;
    if (appliesMutation) committedMutations++;
    return appliesMutation;
  }

  @override
  Future<bool> resetChapter({
    required String novelId,
    required String episodeId,
    bool Function()? canCommit,
  }) async {
    resetEpisodeIds.add(episodeId);
    await beforeMutation;
    if (canCommit?.call() == false) return false;
    if (appliesMutation) committedMutations++;
    return appliesMutation;
  }

  @override
  Future<bool> resetWorkReadingState({
    required String novelId,
    bool Function()? canCommit,
  }) async {
    resetWorkIds.add(novelId);
    await beforeMutation;
    if (canCommit?.call() == false) return false;
    if (appliesMutation) committedMutations++;
    return appliesMutation;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
