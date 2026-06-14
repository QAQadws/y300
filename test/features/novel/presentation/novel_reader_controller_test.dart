import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_transition_state.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_supplemental_hydration_service.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  test('NovelReaderViewState derives episode boundaries', () {
    final episodes = _episodes();

    final first = _viewState(episodes: episodes, currentEpisode: episodes.first);
    expect(first.currentEpisodeIndex, 0);
    expect(first.previousEpisode, isNull);
    expect(first.nextEpisode?.episodeId, episodes[1].episodeId);
    expect(first.hasPreviousEpisode, isFalse);
    expect(first.hasNextEpisode, isTrue);

    final middle = _viewState(episodes: episodes, currentEpisode: episodes[1]);
    expect(middle.currentEpisodeIndex, 1);
    expect(middle.previousEpisode?.episodeId, episodes.first.episodeId);
    expect(middle.nextEpisode?.episodeId, episodes.last.episodeId);
    expect(middle.hasPreviousEpisode, isTrue);
    expect(middle.hasNextEpisode, isTrue);

    final last = _viewState(episodes: episodes, currentEpisode: episodes.last);
    expect(last.currentEpisodeIndex, 2);
    expect(last.previousEpisode?.episodeId, episodes[1].episodeId);
    expect(last.nextEpisode, isNull);
    expect(last.hasPreviousEpisode, isTrue);
    expect(last.hasNextEpisode, isFalse);
  });

  test('NovelReaderController loads readingProgress into state', () async {
    final progress = NovelReadingProgress(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
      scrollOffset: 88,
      updatedAt: DateTime(2026, 6, 1),
    );
    final repository = _ControllerNovelRepository(readingProgress: progress);
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
    );
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final state = await container.read(
      novelReaderControllerProvider(args).future,
    );

    expect(state.readingProgress?.episodeId, 'novel:49:100:5002');
    expect(state.currentOffset, 88);
  });

  test('NovelReaderController previewPreferences only updates effective state', () async {
    final repository = _ControllerNovelRepository();
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    final next = initial.persistedPreferences.copyWith(
      themePreset: NovelReaderThemePreset.sepia,
      flowMode: NovelReaderFlowMode.pagedLtr,
    );

    container.read(provider.notifier).previewPreferences(next);
    final state = container.read(provider).value!;

    expect(state.persistedPreferences, initial.persistedPreferences);
    expect(state.effectivePreferences, next);
    expect(state.progressSnapshot.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(repository.latestPreferences, isNull);
    expect(repository.upsertPreferencesCallCount, 0);
  });

  test('NovelReaderController commitPreferences persists once and syncs state', () async {
    final repository = _ControllerNovelRepository();
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    final next = initial.persistedPreferences.copyWith(
      themePreset: NovelReaderThemePreset.dark,
    );

    container.read(provider.notifier).previewPreferences(next);
    await container.read(provider.notifier).commitPreferences(next);
    final state = container.read(provider).value!;

    expect(repository.latestPreferences, next);
    expect(repository.upsertPreferencesCallCount, 1);
    expect(state.persistedPreferences, next);
    expect(state.effectivePreferences, next);
  });

  test('NovelReaderController revertPreferencePreview rolls back effective state', () async {
    final repository = _ControllerNovelRepository();
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    final next = initial.persistedPreferences.copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );

    container.read(provider.notifier).previewPreferences(next);
    container.read(provider.notifier).revertPreferencePreview();
    final state = container.read(provider).value!;

    expect(state.persistedPreferences, initial.persistedPreferences);
    expect(state.effectivePreferences, initial.persistedPreferences);
    expect(state.progressSnapshot.flowMode, initial.persistedPreferences.flowMode);
    expect(repository.upsertPreferencesCallCount, 0);
  });

  test('NovelReaderController preview and commit are no-op for equal preferences', () async {
    final repository = _ControllerNovelRepository();
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);

    container.read(provider.notifier).previewPreferences(initial.effectivePreferences);
    await container
        .read(provider.notifier)
        .commitPreferences(initial.persistedPreferences);
    final state = container.read(provider).value!;

    expect(state.persistedPreferences, initial.persistedPreferences);
    expect(state.effectivePreferences, initial.effectivePreferences);
    expect(repository.upsertPreferencesCallCount, 0);
  });

  test('NovelReaderController schedules paged page progress without immediate persistence', () async {
    final repository = _ControllerNovelRepository(
      preferences: NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      ),
    );
    final progressCommitter = _FakeNovelReaderProgressCommitter();
    final container = _buildContainer(
      repository: repository,
      progressCommitter: progressCommitter,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    final layout = NovelReaderPageLayout(
      document: _document('novel:49:100:5001'),
      pages: const <NovelReaderPageSlice>[
        NovelReaderPageSlice(index: 0, nodes: <NovelReaderNode>[], anchorNodeId: 'a'),
        NovelReaderPageSlice(index: 1, nodes: <NovelReaderNode>[], anchorNodeId: 'b'),
      ],
    );
    await container.read(provider.notifier).onPagedPageChanged(1, layout);

    final state = await container.read(provider.future);
    expect(state.progressSnapshot.pageIndex, 1);
    expect(state.progressSnapshot.anchorNodeId, 'b');
    expect(progressCommitter.scheduleCallCount, 1);
    expect(progressCommitter.flushCallCount, 0);
    expect(progressCommitter.latestScheduledSnapshot?.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(progressCommitter.latestScheduledSnapshot?.pageIndex, 1);
    expect(repository.readingProgress, isNull);
  });

  test('NovelReaderController saveCurrentProgressNow flushes and syncs readingProgress', () async {
    final repository = _ControllerNovelRepository();
    final progressCommitter = _FakeNovelReaderProgressCommitter();
    final container = _buildContainer(
      repository: repository,
      progressCommitter: progressCommitter,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    const snapshot = NovelReaderProgressSnapshot(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 42,
      pageIndex: 0,
      progressPercent: 0.5,
    );

    await container.read(provider.notifier).saveCurrentProgressNow(snapshot);

    final state = container.read(provider).value!;
    expect(progressCommitter.flushCallCount, 1);
    expect(progressCommitter.latestFlushedSnapshot, snapshot);
    expect(state.progressSnapshot, snapshot);
    expect(state.currentOffset, 42);
    expect(state.readingProgress?.episodeId, 'novel:49:100:5001');
    expect(state.readingProgress?.scrollOffset, 42);
  });

  test('NovelReaderController onScrollOffsetChanged schedules progress update', () async {
    final repository = _ControllerNovelRepository();
    final progressCommitter = _FakeNovelReaderProgressCommitter();
    final container = _buildContainer(
      repository: repository,
      progressCommitter: progressCommitter,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    await container.read(provider.notifier).onScrollOffsetChanged(
      24,
      maxScrollExtent: 120,
    );

    final state = container.read(provider).value!;
    expect(state.currentOffset, 24);
    expect(state.progressSnapshot.scrollOffset, 24);
    expect(progressCommitter.scheduleCallCount, 1);
    expect(progressCommitter.flushCallCount, 0);
    expect(repository.readingProgress, isNull);
  });

  test('NovelReaderController dispose cancels progress committer', () async {
    final repository = _ControllerNovelRepository();
    final progressCommitter = _FakeNovelReaderProgressCommitter();
    final container = _buildContainer(
      repository: repository,
      progressCommitter: progressCommitter,
    );
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final subscription = _keepReaderAlive(container, args);

    await container.read(novelReaderControllerProvider(args).future);
    subscription.close();
    container.dispose();

    expect(progressCommitter.cancelCallCount, 1);
  });

  test('openEpisodeFromCatalog loads target and preserves target progress', () async {
    final targetProgress = NovelReadingProgress(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5002',
      scrollOffset: 88,
      updatedAt: DateTime(2026, 6, 1),
    );
    final repository = _ControllerNovelRepository(
      readingProgress: targetProgress,
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    expect(initial.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(initial.currentOffset, 0);

    final controller = container.read(provider.notifier);
    await controller.saveCurrentOffsetNow(12);
    await controller.openEpisodeFromCatalog('novel:49:100:5002');

    final state = await container.read(provider.future);
    expect(state.currentEpisode.episodeId, 'novel:49:100:5002');
    expect(state.currentOffset, 88);
    expect(repository.savedProgressEpisodeIds, contains('novel:49:100:5001'));
  });

  test('initial build publishes critical state before supplemental completes', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(
        episodeId: 'novel:49:100:5001',
      ),
    );
    final hydrationService = _ControlledNovelReaderSupplementalHydrationService();
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      supplementalHydrationService: hydrationService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final state = await container.read(provider.future);

    expect(state.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(state.isHydratingSupplemental, isTrue);
    expect(state.novel, isNull);
    expect(state.bookmarks, isEmpty);

    hydrationService.completeInitialBookmarks(
      _supplementalBookmarks(episodeId: 'novel:49:100:5001'),
    );
    await Future<void>.delayed(Duration.zero);
    var hydrated = container.read(provider).value!;
    expect(hydrated.bookmarks, isNotEmpty);
    expect(hydrated.currentEpisodeBookmarks, isNotEmpty);
    expect(hydrated.downloadedEpisodeIds, isEmpty);
    expect(hydrated.novel, isNull);

    hydrationService.completeInitialDownloadedEpisodeIds(
      const <String>{'novel:49:100:5001'},
    );
    await Future<void>.delayed(Duration.zero);
    hydrated = container.read(provider).value!;
    expect(hydrated.downloadedEpisodeIds, contains('novel:49:100:5001'));

    hydrationService.completeInitialNovel(_supplementalNovel());
    await Future<void>.delayed(Duration.zero);

    hydrated = container.read(provider).value!;
    expect(hydrated.isHydratingSupplemental, isFalse);
    expect(hydrated.novel?.title, '测试小说');
    expect(hydrated.downloadedEpisodeIds, contains('novel:49:100:5001'));
  });

  test('openEpisodeFromCatalog keeps old content and sets switching transition before critical resolves', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(
        episodeId: 'novel:49:100:5001',
      ),
    );
    final hydrationService = _ControlledNovelReaderSupplementalHydrationService();
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      supplementalHydrationService: hydrationService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    hydrationService.completeInitialBookmarks(
      _supplementalBookmarks(episodeId: 'novel:49:100:5001'),
    );
    hydrationService.completeInitialDownloadedEpisodeIds(
      const <String>{'novel:49:100:5001'},
    );
    hydrationService.completeInitialNovel(_supplementalNovel());
    await Future<void>.delayed(Duration.zero);

    final future = container
        .read(provider.notifier)
        .openEpisodeFromCatalog('novel:49:100:5002');
    final transitioning = container.read(provider).value!;

    expect(container.read(provider).isLoading, isFalse);
    expect(transitioning.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(
      transitioning.transition?.kind,
      NovelReaderTransitionKind.switchingEpisode,
    );
    expect(
      transitioning.transition?.targetEpisodeId,
      'novel:49:100:5002',
    );

    bootstrapService.completeEpisodeCritical(
      'novel:49:100:5002',
      _criticalBootstrap(
        episodeId: 'novel:49:100:5002',
        paragraphText: '第二章正文。',
      ),
    );
    final didSucceed = await future;

    expect(didSucceed, isTrue);
    final switched = container.read(provider).value!;
    expect(switched.currentEpisode.episodeId, 'novel:49:100:5002');
    expect(switched.transition, isNull);
    expect(switched.searchKeyword, isEmpty);
    expect(switched.searchResults, isEmpty);
    expect(switched.currentSearchIndex, -1);
    expect(switched.isHydratingSupplemental, isTrue);
  });

  test('openEpisodeFromCatalog failure keeps old chapter and clears transition', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(
        episodeId: 'novel:49:100:5001',
      ),
    );
    bootstrapService.failEpisodeCritical(
      'novel:49:100:5002',
      StateError('critical failed'),
    );
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);

    final didSucceed = await container
        .read(provider.notifier)
        .openEpisodeFromCatalog('novel:49:100:5002');

    expect(didSucceed, isFalse);
    final state = container.read(provider).value!;
    expect(state.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(state.transition, isNull);
  });

  test('stale supplemental does not override newer chapter state', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(
        episodeId: 'novel:49:100:5001',
      ),
    );
    final hydrationService = _ControlledNovelReaderSupplementalHydrationService();
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      supplementalHydrationService: hydrationService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);

    final switchFuture = container
        .read(provider.notifier)
        .openEpisodeFromCatalog('novel:49:100:5002');
    bootstrapService.completeEpisodeCritical(
      'novel:49:100:5002',
      _criticalBootstrap(
        episodeId: 'novel:49:100:5002',
        paragraphText: '第二章正文。',
      ),
    );
    await switchFuture;

    hydrationService.completeInitialBookmarks(
      _supplementalBookmarks(
        episodeId: 'novel:49:100:5001',
      ),
    );
    hydrationService.completeInitialDownloadedEpisodeIds(
      const <String>{'novel:49:100:5001'},
    );
    hydrationService.completeInitialNovel(
      _supplementalNovel(novelTitle: '旧章节小说'),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(provider).value!;
    expect(state.currentEpisode.episodeId, 'novel:49:100:5002');
    expect(state.novel, isNull);
    expect(state.downloadedEpisodeIds, isEmpty);
  });

  test('supplemental phase failure does not block later phases', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(
        episodeId: 'novel:49:100:5001',
      ),
    );
    final hydrationService = _ControlledNovelReaderSupplementalHydrationService();
    hydrationService.failInitialBookmarks(StateError('bookmark failed'));
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
      supplementalHydrationService: hydrationService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    hydrationService.completeInitialDownloadedEpisodeIds(
      const <String>{'novel:49:100:5001'},
    );
    hydrationService.completeInitialNovel(_supplementalNovel());
    await Future<void>.delayed(Duration.zero);

    final state = container.read(provider).value!;
    expect(state.bookmarks, isEmpty);
    expect(state.downloadedEpisodeIds, contains('novel:49:100:5001'));
    expect(state.novel?.title, '测试小说');
    expect(state.isHydratingSupplemental, isFalse);
  });

  test('refreshCurrentEpisode failure keeps old content and avoids AsyncError', () async {
    final repository = _ControllerNovelRepository();
    final bootstrapService = _ControlledNovelReaderBootstrapService(
      initialCritical: _criticalBootstrap(
        episodeId: 'novel:49:100:5001',
      ),
    );
    bootstrapService.failEpisodeCritical(
      'novel:49:100:5001',
      StateError('refresh failed'),
    );
    final container = _buildContainer(
      repository: repository,
      bootstrapService: bootstrapService,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);

    final didSucceed = await container.read(provider.notifier).refreshCurrentEpisode();

    expect(didSucceed, isFalse);
    expect(container.read(provider).hasError, isFalse);
    final state = container.read(provider).value!;
    expect(state.currentEpisode.episodeId, 'novel:49:100:5001');
    expect(state.transition, isNull);
  });

  test('searchInCurrentChapter updates search results and selection', () async {
    final repository = _ControllerNovelRepository();
    repository.contentsByEpisodeId['novel:49:100:5001'] = _content(
      'novel:49:100:5001',
      '关键词在这里。关键词再次出现。',
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    container.read(provider.notifier).searchInCurrentChapter('关键词');
    final state = container.read(provider).value!;

    expect(state.searchResults, hasLength(2));
    expect(state.currentSearchIndex, 0);
    container
        .read(provider.notifier)
        .selectSearchResult(state.searchResults.last.resultId);
    expect(container.read(provider).value!.currentSearchIndex, 1);
  });

  test('bookmark actions persist and reload state', () async {
    final repository = _ControllerNovelRepository();
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    await container.read(provider.future);
    await container.read(provider.notifier).toggleCurrentEpisodeBookmark();
    expect(container.read(provider).value!.hasCurrentEpisodeBookmark, isTrue);

    await container.read(provider.notifier).addBookmarkAtCurrentPosition(
          const NovelReaderTextAnchor(
            episodeId: 'novel:49:100:5001',
            nodeId: 'node-0',
          ),
        );
    var state = container.read(provider).value!;
    expect(state.currentEpisodeBookmarks.length, 2);

    final positionBookmark = state.currentEpisodeBookmarks.firstWhere(
      (bookmark) => bookmark.bookmarkId.startsWith('reader-bookmark:'),
    );
    await container
        .read(provider.notifier)
        .removeBookmark(positionBookmark.bookmarkId);
    state = container.read(provider).value!;
    expect(state.currentEpisodeBookmarks.length, 1);
  });

  test('cacheCurrentEpisode updates downloaded state', () async {
    final repository = _ControllerNovelRepository();
    final downloadService = _RecordingNovelDownloadService();
    final stateRepository = _MemoryLibraryStateRepository();
    final container = _buildContainer(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    expect(initial.isHydratingSupplemental, isTrue);
    expect(initial.isCurrentEpisodeDownloaded, isFalse);
    final result = await container.read(provider.notifier).cacheCurrentEpisode();
    final state = container.read(provider).value!;

    expect(result.successCount, 1);
    expect(downloadService.downloadedEpisodeIds, <String>['novel:49:100:5001']);
    expect(state.isCurrentEpisodeDownloaded, isTrue);
    expect(state.isCachingEpisodes, isFalse);
  });

  test('deleteCurrentEpisodeCache clears downloaded state', () async {
    final repository = _ControllerNovelRepository();
    final downloadService = _RecordingNovelDownloadService();
    final stateRepository = _MemoryLibraryStateRepository();
    await stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: 'novel:49:100:5001',
      workId: 'novel:49:100',
      isDownloaded: true,
      downloadedAt: DateTime(2026, 6, 8),
    );
    final container = _buildContainer(
      repository: repository,
      downloadService: downloadService,
      stateRepository: stateRepository,
    );
    addTearDown(container.dispose);
    const args = NovelReaderArgs(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
    );
    final provider = novelReaderControllerProvider(args);
    final subscription = _keepReaderAlive(container, args);
    addTearDown(subscription.close);

    final initial = await container.read(provider.future);
    expect(initial.isHydratingSupplemental, isTrue);
    expect(initial.isCurrentEpisodeDownloaded, isFalse);

    final result =
        await container.read(provider.notifier).deleteCurrentEpisodeCache();
    final state = container.read(provider).value!;

    expect(result.successCount, 1);
    expect(downloadService.deletedEpisodeIds, <String>['novel:49:100:5001']);
    expect(state.isCurrentEpisodeDownloaded, isFalse);
  });
}

ProviderSubscription<AsyncValue<NovelReaderViewState>> _keepReaderAlive(
  ProviderContainer container,
  NovelReaderArgs args,
) {
  return container.listen<AsyncValue<NovelReaderViewState>>(
    novelReaderControllerProvider(args),
    (_, _) {},
  );
}

ProviderContainer _buildContainer({
  required _ControllerNovelRepository repository,
  NovelDownloadService? downloadService,
  LibraryStateRepository? stateRepository,
  NovelReaderBootstrapService? bootstrapService,
  NovelReaderSupplementalHydrationService? supplementalHydrationService,
  NovelReaderDocumentBuildService? documentBuildService,
  NovelReaderProgressCommitter? progressCommitter,
}) {
  return ProviderContainer(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      novelDownloadServiceProvider.overrideWithValue(
        downloadService ?? _NoopNovelDownloadService(),
      ),
      libraryStateRepositoryProvider.overrideWithValue(
        stateRepository ?? _MemoryLibraryStateRepository(),
      ),
      if (bootstrapService != null)
        novelReaderBootstrapServiceProvider.overrideWithValue(bootstrapService),
      if (supplementalHydrationService != null)
        novelReaderSupplementalHydrationServiceProvider.overrideWithValue(
          supplementalHydrationService,
        ),
      if (documentBuildService != null)
        novelReaderDocumentBuildServiceProvider.overrideWithValue(
          documentBuildService,
        ),
      if (progressCommitter != null)
        novelReaderProgressCommitterProvider.overrideWithValue(progressCommitter),
    ],
  );
}

NovelReaderViewState _viewState({
  required List<NovelEpisodeItem> episodes,
  required NovelEpisodeItem currentEpisode,
}) {
  return NovelReaderViewState(
    novel: null,
    episodes: episodes,
    currentEpisode: currentEpisode,
    currentContent: _content(currentEpisode.episodeId, '正文。'),
    document: _document(currentEpisode.episodeId),
    persistedPreferences: NovelReaderPreferences.defaults(),
    effectivePreferences: NovelReaderPreferences.defaults(),
    readingProgress: null,
    progressSnapshot: const NovelReaderProgressSnapshot(
      novelId: 'novel:49:100',
      episodeId: 'novel:49:100:5001',
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: 0,
      pageIndex: 0,
      progressPercent: 0,
    ),
    currentOffset: 0,
  );
}

class _NoopNovelDownloadService implements NovelDownloadService {
  @override
  Future<void> deleteChapterDownload({
    required String novelId,
    required String episodeId,
  }) async {}

  @override
  Future<DownloadedNovelChapter> downloadChapter({
    required String novelId,
    required String episodeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    return null;
  }
}

class _RecordingNovelDownloadService implements NovelDownloadService {
  final downloadedEpisodeIds = <String>[];
  final deletedEpisodeIds = <String>[];

  @override
  Future<void> deleteChapterDownload({
    required String novelId,
    required String episodeId,
  }) async {
    deletedEpisodeIds.add(episodeId);
  }

  @override
  Future<DownloadedNovelChapter> downloadChapter({
    required String novelId,
    required String episodeId,
  }) async {
    downloadedEpisodeIds.add(episodeId);
    return DownloadedNovelChapter(
      novelId: novelId,
      episodeId: episodeId,
      chapterPath: '/tmp/$episodeId.json',
    );
  }

  @override
  Future<NovelChapterContent?> getDownloadedChapterContent({
    required String novelId,
    required String episodeId,
  }) async {
    return null;
  }
}

class _MemoryLibraryStateRepository implements LibraryStateRepository {
  final Map<String, LibraryEpisodeState> _episodeStates =
      <String, LibraryEpisodeState>{};

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
  }) async {
    final old = _episodeStates[episodeId];
    _episodeStates[episodeId] = LibraryEpisodeState(
      moduleKey: moduleKey,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead ?? old?.isRead ?? false,
      isDownloaded: isDownloaded ?? old?.isDownloaded ?? false,
      isBookmarked: isBookmarked ?? old?.isBookmarked ?? false,
      readAt: isRead == false ? null : readAt ?? old?.readAt,
      downloadedAt: isDownloaded == false
          ? null
          : downloadedAt ?? old?.downloadedAt,
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    final state = _episodeStates[episodeId];
    return state?.moduleKey == moduleKey ? state : null;
  }

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return _episodeStates.values
        .where(
          (state) =>
              state.moduleKey == moduleKey &&
              state.workId == workId &&
              state.isDownloaded,
        )
        .length;
  }

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    _episodeStates.removeWhere(
      (_, state) => state.moduleKey == moduleKey && state.workId == workId,
    );
  }

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 6, 8),
    );
  }

  @override
  Future<String> createTag({required String name}) async => 'tag';

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<void> renameTag({required String tagId, required String newName}) async {}

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const <LibraryTag>[];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }
}

class _ControllerNovelRepository implements NovelRepository {
  _ControllerNovelRepository({
    this.readingProgress,
    NovelReaderPreferences? preferences,
  }) : preferences = preferences ?? NovelReaderPreferences.defaults() {
    contentsByEpisodeId = <String, NovelChapterContent>{
      for (final episode in episodes)
        episode.episodeId: _content(episode.episodeId, '${episode.episodeTitle}正文。'),
    };
  }

  final episodes = _episodes();
  late final Map<String, NovelChapterContent> contentsByEpisodeId;
  NovelReadingProgress? readingProgress;
  NovelReaderPreferences preferences;
  NovelReaderPreferences? latestPreferences;
  int upsertPreferencesCallCount = 0;
  final savedProgressEpisodeIds = <String>[];
  final bookmarks = <NovelReaderBookmark>[];

  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return const <NovelShelfCategory>[];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    return contentsByEpisodeId[episodeId];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: '测试小说',
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: episodes.length,
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return descending ? episodes.reversed.toList(growable: false) : episodes;
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    return preferences;
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    return readingProgress;
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <NovelItem>[];
  }

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
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: episodes.length,
    );
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {
    savedProgressEpisodeIds.add(episodeId);
    readingProgress = NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: scrollOffset,
      updatedAt: DateTime(2026, 6, 8),
      flowMode: flowMode,
      pageIndex: pageIndex,
      anchorNodeId: anchorNodeId,
      progressPercent: progressPercent,
    );
  }

  @override
  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {
    upsertPreferencesCallCount += 1;
    latestPreferences = preferences;
    this.preferences = preferences;
  }

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    bookmarks.removeWhere((item) => item.bookmarkId == bookmark.bookmarkId);
    bookmarks.add(bookmark);
  }

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return bookmarks.where((bookmark) => bookmark.novelId == novelId).toList();
  }

  @override
  Future<void> removeReaderBookmark({
    required String bookmarkId,
  }) async {
    bookmarks.removeWhere((bookmark) => bookmark.bookmarkId == bookmarkId);
  }

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    bookmarks.removeWhere((bookmark) => bookmark.bookmarkId == 'episode-bookmark:$episodeId');
    if (isBookmarked) {
      bookmarks.add(
        NovelReaderBookmark(
          bookmarkId: 'episode-bookmark:$episodeId',
          novelId: novelId,
          episodeId: episodeId,
          anchor: NovelReaderTextAnchor(episodeId: episodeId),
          title: episodeId,
          snippet: '章节书签',
          createdAt: DateTime(2026, 6, 8),
          updatedAt: DateTime(2026, 6, 8),
        ),
      );
    }
  }
}

class _ControlledNovelReaderBootstrapService
    implements NovelReaderBootstrapService {
  _ControlledNovelReaderBootstrapService({
    required NovelReaderCriticalBootstrap initialCritical,
  }) : _initialCritical = initialCritical;

  final NovelReaderCriticalBootstrap _initialCritical;
  bool _hasServedInitialCritical = false;
  final Map<String, Completer<NovelReaderCriticalBootstrap>> _criticalCompleters =
      <String, Completer<NovelReaderCriticalBootstrap>>{};
  final Map<String, Object> _criticalFailures = <String, Object>{};

  @override
  Future<NovelReaderCriticalBootstrap> loadCritical(
    NovelReaderLoadContext context,
  ) {
    if (!_hasServedInitialCritical &&
        context.requestedEpisodeId == _initialCritical.currentEpisode.episodeId) {
      _hasServedInitialCritical = true;
      return Future<NovelReaderCriticalBootstrap>.value(_initialCritical);
    }
    final failure = _criticalFailures[context.requestedEpisodeId];
    if (failure != null) {
      return Future<NovelReaderCriticalBootstrap>.error(failure);
    }
    final completer = _criticalCompleters.putIfAbsent(
      context.requestedEpisodeId,
      Completer<NovelReaderCriticalBootstrap>.new,
    );
    return completer.future;
  }

  void completeEpisodeCritical(
    String episodeId,
    NovelReaderCriticalBootstrap value,
  ) {
    _criticalCompleters.putIfAbsent(
      episodeId,
      Completer<NovelReaderCriticalBootstrap>.new,
    );
    final completer = _criticalCompleters[episodeId]!;
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void failEpisodeCritical(String episodeId, Object error) {
    _criticalFailures[episodeId] = error;
  }
}

List<NovelEpisodeItem> _episodes() {
  return const <NovelEpisodeItem>[
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5001',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5001',
      sourcePage: 1,
      episodeTitle: '第1章',
      orderIndex: 0,
      datelineText: '2026-05-03',
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5002',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5002',
      sourcePage: 1,
      episodeTitle: '第2章',
      orderIndex: 1,
      datelineText: '2026-05-04',
    ),
    NovelEpisodeItem(
      episodeId: 'novel:49:100:5003',
      novelId: 'novel:49:100',
      sourceTid: '100',
      sourcePid: '5003',
      sourcePage: 1,
      episodeTitle: '第3章',
      orderIndex: 2,
      datelineText: '2026-05-05',
    ),
  ];
}

NovelChapterContent _content(String episodeId, String text) {
  return NovelChapterContent(
    episodeId: episodeId,
    rawHtml: '<p>$text</p>',
    plainText: text,
    paragraphs: <String>[text],
  );
}

NovelReaderDocument _document(String episodeId) {
  return NovelReaderDocument(
    episodeId: episodeId,
    rawHtmlHash: 'test',
    nodes: <NovelReaderNode>[
      NovelReaderNode(
        id: 'node-0',
        type: NovelReaderNodeType.paragraph,
        text: '正文。',
      ),
    ],
    plainText: '正文。',
    wordCount: 3,
  );
}

NovelReaderCriticalBootstrap _criticalBootstrap({
  required String episodeId,
  String paragraphText = '正文。',
  NovelReaderPreferences? preferences,
  NovelReadingProgress? readingProgress,
}) {
  final resolvedPreferences = preferences ?? NovelReaderPreferences.defaults();
  final progress = const NovelReaderProgressPolicy().fromReadingProgress(
    novelId: 'novel:49:100',
    episodeId: episodeId,
    flowMode: resolvedPreferences.flowMode,
    progress: readingProgress,
  );
  final episode = _episodes().firstWhere((item) => item.episodeId == episodeId);
  return NovelReaderCriticalBootstrap(
    episodes: _episodes(),
    currentEpisode: episode,
    currentContent: _content(episodeId, paragraphText),
    document: NovelReaderDocument(
      episodeId: episodeId,
      rawHtmlHash: 'test-$episodeId',
      nodes: <NovelReaderNode>[
        NovelReaderNode(
          id: 'node-0',
          type: NovelReaderNodeType.paragraph,
          text: paragraphText,
        ),
      ],
      plainText: paragraphText,
      wordCount: paragraphText.length,
    ),
    persistedPreferences: resolvedPreferences,
    effectivePreferences: resolvedPreferences,
    readingProgress: readingProgress,
    progressSnapshot: progress,
    currentOffset: progress.scrollOffset,
  );
}

List<NovelReaderBookmark> _supplementalBookmarks({
  required String episodeId,
}) {
  return <NovelReaderBookmark>[
    NovelReaderBookmark(
      bookmarkId: 'episode-bookmark:$episodeId',
      novelId: 'novel:49:100',
      episodeId: episodeId,
      anchor: NovelReaderTextAnchor(episodeId: episodeId),
      title: '章节书签',
      snippet: '章节书签',
      createdAt: DateTime(2026, 6, 8),
      updatedAt: DateTime(2026, 6, 8),
    ),
  ];
}

NovelItem _supplementalNovel({
  String novelTitle = '测试小说',
}) {
  return NovelItem(
    novelId: 'novel:49:100',
    sourceTid: '100',
    sourceFid: '49',
    title: novelTitle,
    updatedAt: DateTime(2026, 1, 1),
    episodeCount: _episodes().length,
  );
}

class _ControlledNovelReaderSupplementalHydrationService
    implements NovelReaderSupplementalHydrationService {
  final _HydrationSequence<List<NovelReaderBookmark>> _bookmarkSequence =
      _HydrationSequence<List<NovelReaderBookmark>>();
  final _HydrationSequence<Set<String>> _downloadedEpisodeIdsSequence =
      _HydrationSequence<Set<String>>();
  final _HydrationSequence<NovelItem?> _novelSequence =
      _HydrationSequence<NovelItem?>();

  @override
  Future<List<NovelReaderBookmark>> loadBookmarks({
    required String novelId,
  }) {
    return _bookmarkSequence.take();
  }

  @override
  Future<Set<String>> loadDownloadedEpisodeIds({
    required String novelId,
    required Iterable<String> episodeIds,
  }) {
    return _downloadedEpisodeIdsSequence.take();
  }

  @override
  Future<NovelItem?> loadNovel({
    required String novelId,
  }) {
    return _novelSequence.take();
  }

  void completeInitialBookmarks(List<NovelReaderBookmark> value) {
    _bookmarkSequence.completeAt(0, value);
  }

  void failInitialBookmarks(Object error) {
    _bookmarkSequence.completeErrorAt(0, error);
  }

  void completeInitialDownloadedEpisodeIds(Set<String> value) {
    _downloadedEpisodeIdsSequence.completeAt(0, value);
  }

  void completeInitialNovel(NovelItem? value) {
    _novelSequence.completeAt(0, value);
  }
}

class _FakeNovelReaderProgressCommitter
    implements NovelReaderProgressCommitter {
  int scheduleCallCount = 0;
  int flushCallCount = 0;
  int cancelCallCount = 0;
  NovelReaderProgressSnapshot? latestScheduledSnapshot;
  NovelReaderProgressSnapshot? latestFlushedSnapshot;

  @override
  void cancel() {
    cancelCallCount += 1;
  }

  @override
  Future<void> flush(NovelReaderProgressSnapshot snapshot) async {
    flushCallCount += 1;
    latestFlushedSnapshot = snapshot;
  }

  @override
  void schedule(NovelReaderProgressSnapshot snapshot) {
    scheduleCallCount += 1;
    latestScheduledSnapshot = snapshot;
  }
}

class _HydrationSequence<T> {
  final List<_PendingHydrationOutcome<T>?> _pendingOutcomes =
      <_PendingHydrationOutcome<T>?>[];
  final List<Completer<T>?> _completers = <Completer<T>?>[];
  int _nextTakeIndex = 0;

  Future<T> take() {
    final index = _nextTakeIndex++;
    _ensureIndex(index);
    final pendingOutcome = _pendingOutcomes[index];
    if (pendingOutcome != null) {
      return pendingOutcome.toFuture();
    }
    final completer = Completer<T>();
    _completers[index] = completer;
    return completer.future;
  }

  void completeAt(int index, T value) {
    _ensureIndex(index);
    final completer = _completers[index];
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
      return;
    }
    _pendingOutcomes[index] = _PendingHydrationValue<T>(value);
  }

  void completeErrorAt(int index, Object error) {
    _ensureIndex(index);
    final completer = _completers[index];
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
      return;
    }
    _pendingOutcomes[index] = _PendingHydrationError<T>(error);
  }

  void _ensureIndex(int index) {
    while (_pendingOutcomes.length <= index) {
      _pendingOutcomes.add(null);
      _completers.add(null);
    }
  }
}

abstract class _PendingHydrationOutcome<T> {
  Future<T> toFuture();
}

class _PendingHydrationValue<T> implements _PendingHydrationOutcome<T> {
  _PendingHydrationValue(this.value);

  final T value;

  @override
  Future<T> toFuture() {
    return Future<T>.value(value);
  }
}

class _PendingHydrationError<T> implements _PendingHydrationOutcome<T> {
  _PendingHydrationError(this.error);

  final Object error;

  @override
  Future<T> toFuture() {
    return Future<T>.error(error);
  }
}
