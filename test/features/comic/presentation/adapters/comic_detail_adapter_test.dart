import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/comic/presentation/adapters/comic_detail_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';

void main() {
  test('refreshWork uses catalog fast path when catalogUrl is persisted', () async {
    final repository = _FakeComicRepository(catalogUrl: 'https://example.com/catalog');
    final refreshService = _FakeComicEpisodeRefreshService();
    final queue = _RecordingSearchQueue();
    final applier = _RecordingRefreshOutcomeApplier();
    final adapter = ComicDetailAdapter(
      repository,
      refreshService: refreshService,
      searchQueue: queue,
      refreshOutcomeApplier: applier,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final result = await adapter.refreshWork(workId: 'comic:1');

    expect(result.status, DetailRefreshStatus.immediate);
    expect(applier.requests, hasLength(1));
    expect(applier.requests.single.comicId, 'comic:1');
    expect(applier.requests.single.source, ComicEpisodeRefreshSource.catalog);
    expect(
      applier.requests.single.reason,
      'comic_detail_catalog_direct_refresh',
    );
    expect(queue.enqueuedRequests, isEmpty);
  });

  test('refreshWork uses incremental discovery when no catalogUrl', () async {
    final repository = _FakeComicRepository();
    final refreshService = _FakeComicEpisodeRefreshService(
      catalogOutcome: const ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.empty,
        links: <ComicEpisodeLink>[],
      ),
    );
    final discovery = _FakeDiscoveryService(
      threadResult: const ParsedThreadResult(
        episodeLinks: [
          ComicEpisodeLink(url: 'thread-201-1-1.html', rawText: '第1话'),
          ComicEpisodeLink(url: 'thread-202-1-1.html', rawText: '第2话'),
          ComicEpisodeLink(url: 'thread-203-1-1.html', rawText: '第3话'),
        ],
        recursiveTidCandidates: [],
        catalogUrl: null,
      ),
    );
    final incremental = _FakeIncrementalDiscovery(
      directResult: const [
        ComicEpisodeLink(url: 'thread-203-1-1.html', rawText: '第3话'),
      ],
    );
    final queue = _RecordingSearchQueue();
    final applier = _RecordingRefreshOutcomeApplier();
    final adapter = ComicDetailAdapter(
      repository,
      refreshService: refreshService,
      searchQueue: queue,
      refreshOutcomeApplier: applier,
      incrementalDiscovery: incremental,
      discoveryService: discovery,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final result = await adapter.refreshWork(workId: 'comic:1');

    expect(result.status, DetailRefreshStatus.immediate);
    expect(applier.requests, hasLength(1));
    expect(
      applier.requests.single.reason,
      'comic_detail_incremental_refresh',
    );
    expect(applier.requests.single.links, hasLength(1));
    expect(discovery.fetchAndParseThreadCalls, 1);
  });

  test('refreshWork enqueues and returns queued when no incremental links', () async {
    final repository = _FakeComicRepository();
    final refreshService = _FakeComicEpisodeRefreshService(
      catalogOutcome: const ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.empty,
        links: <ComicEpisodeLink>[],
      ),
    );
    final queue = _RecordingSearchQueue();
    final applier = _RecordingRefreshOutcomeApplier();
    final adapter = ComicDetailAdapter(
      repository,
      refreshService: refreshService,
      searchQueue: queue,
      refreshOutcomeApplier: applier,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final result = await adapter.refreshWork(workId: 'comic:1');

    // No discovery service → no incremental links → returns queued
    expect(result.status, DetailRefreshStatus.queued);
    expect(queue.enqueuedOrigins, <ComicSearchRefreshOrigin>[
      ComicSearchRefreshOrigin.detailManual,
    ]);
    expect(queue.enqueuedRequests.single.comicId, 'comic:1');
    expect(queue.enqueuedRequests.single.sourceTid, '100');
    expect(queue.enqueuedRequests.single.customSearchTitle, 'Search Test Comic');
    expect(queue.enqueuedTitles, <String>['Search Test Comic']);
  });

  test('refreshWork enqueues cleaned display title when no custom search title is set', () async {
    final repository = _FakeComicRepository(title: '[Scan] Noisy Title Vol.2');
    final refreshService = _FakeComicEpisodeRefreshService(
      catalogOutcome: const ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.empty,
        links: <ComicEpisodeLink>[],
      ),
    );
    final queue = _RecordingSearchQueue();
    final adapter = ComicDetailAdapter(
      repository,
      refreshService: refreshService,
      searchQueue: queue,
      refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
      featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
        readerCustomMetadataEnabled: false,
      ),
      stateRepository: _FakeLibraryStateRepository(),
    );

    final result = await adapter.refreshWork(workId: 'comic:1');

    expect(result.status, DetailRefreshStatus.queued);
    // Custom search title is suppressed, so the queue title is the analyzer's
    // clean book name rather than the raw "[Scan] Noisy Title Vol.2" thread.
    expect(queue.enqueuedTitles, <String>['Noisy Title']);
  });

  test('custom metadata feature flag can fall back to source fields', () async {
    final repository = _FakeComicRepositoryWithCoverWriter(
      customCoverImageUrl: 'https://img.test/custom-cover.jpg',
    );
    final cacheService = _FakeImageCacheService(localPath: '/cache/custom-cover.jpg');
    final refreshService = _FakeComicEpisodeRefreshService();
    final adapter = ComicDetailAdapter(
      repository,
      refreshService: refreshService,
      refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
      imageCacheService: cacheService,
      featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
        readerCustomMetadataEnabled: false,
      ),
      stateRepository: _FakeLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'comic:1');
    await adapter.refreshWork(workId: 'comic:1');

    expect(header.title, 'Source Test Comic');
    expect(header.customTitle, isNull);
    expect(header.coverImageUrl, 'https://img.test/90-1.jpg');
    expect(header.customCoverImageUrl, isNull);
    expect(header.customCoverLocalPath, isNull);
    expect(repository.lastCustomCoverLocalPath, isNull);
    expect(header.author, 'Source Author');
    expect(header.customAuthor, isNull);
    expect(header.translationGroup, 'Source Group');
    expect(header.customTranslationGroup, isNull);
    expect(header.customSearchTitle, isNull);
    expect(refreshService.lastRequest?.customTitle, isNull);
    expect(refreshService.lastRequest?.customSearchTitle, isNull);
  });

  test('loadHeader falls back to first image of smallest tid episode', () async {
    final repository = _FakeComicRepository();
    final adapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'comic:1');

    expect(header.coverImageUrl, 'https://img.test/90-1.jpg');
  });

  test('loadHeader caches first episode cover and writes local path', () async {
    final repository = _FakeComicRepositoryWithCoverWriter();
    final cacheService = _FakeImageCacheService(localPath: '/cache/cover.jpg');
    final adapter = ComicDetailAdapter(
      repository,
      imageCacheService: cacheService,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'comic:1');

    expect(header.coverLocalPath, '/cache/cover.jpg');
    expect(cacheService.lastRequest?.cacheKey, 'cover/comic/comic:1');
    expect(repository.lastCoverImageUrl, 'https://img.test/90-1.jpg');
    expect(repository.lastCoverLocalPath, '/cache/cover.jpg');
  });

  test('loadHeader caches custom cover into custom local path', () async {
    final repository = _FakeComicRepositoryWithCoverWriter(
      customCoverImageUrl: 'https://img.test/custom-cover.jpg',
    );
    final cacheService = _FakeImageCacheService(localPath: '/cache/custom-cover.jpg');
    final adapter = ComicDetailAdapter(
      repository,
      imageCacheService: cacheService,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final header = await adapter.loadHeader(workId: 'comic:1');

    expect(header.customCoverLocalPath, '/cache/custom-cover.jpg');
    expect(cacheService.lastRequest?.cacheKey, 'cover/custom/comic/comic:1');
    expect(cacheService.lastRequest?.role, ImageCacheRole.customCover);
    expect(repository.lastCoverImageUrl, isNull);
    expect(repository.lastCoverLocalPath, isNull);
    expect(repository.lastCustomCoverLocalPath, '/cache/custom-cover.jpg');
  });

  test('getReaderRouteTarget continues from reading progress first', () async {
    final repository = _FakeComicRepository(
      progress: ComicReadingProgress(
        comicId: 'comic:1',
        episodeId: 'comic:1:90',
        imageIndex: 2,
        scrollOffset: 120,
        updatedAt: DateTime(2026, 5, 12),
      ),
    );
    final adapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(
        workState: LibraryWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'comic:1',
          lastReadEpisodeId: 'comic:1:120',
          lastReadAt: DateTime(2026, 5, 12),
          createdAt: DateTime(2026, 5, 12),
          updatedAt: DateTime(2026, 5, 12),
        ),
      ),
    );

    final target = await adapter.getReaderRouteTarget(
      workId: 'comic:1',
      preferContinue: true,
    );

    expect(target?.episodeId, 'comic:1:90');
  });

  test('getReaderRouteTarget falls back to library work state', () async {
    final repository = _FakeComicRepository();
    final adapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(
        workState: LibraryWorkState(
          moduleKey: LibraryModuleKey.comic,
          workId: 'comic:1',
          lastReadEpisodeId: 'comic:1:120',
          lastReadAt: DateTime(2026, 5, 12),
          createdAt: DateTime(2026, 5, 12),
          updatedAt: DateTime(2026, 5, 12),
        ),
      ),
    );

    final target = await adapter.getReaderRouteTarget(
      workId: 'comic:1',
      preferContinue: true,
    );

    expect(target?.episodeId, 'comic:1:120');
  });

  test('getReaderRouteTarget starts from first unread chapter without progress', () async {
    final repository = _FakeComicRepository();
    final adapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(
        episodeStates: <String, LibraryEpisodeState>{
          'comic:1:120': LibraryEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic:1:120',
            workId: 'comic:1',
            isRead: true,
          ),
        },
      ),
    );

    final target = await adapter.getReaderRouteTarget(
      workId: 'comic:1',
      preferContinue: true,
    );

    expect(target?.episodeId, 'comic:1:90');
  });

  test('clearAllReadState delegates to ReadingStateBatchWriter when injected', () async {
    final writer = _RecordingReadingStateBatchWriter();
    final adapter = ComicDetailAdapter(
      _FakeComicRepository(),
      readingStateBatchWriter: writer,
      stateRepository: _FakeLibraryStateRepository(),
    );

    await adapter.clearAllReadState(workId: 'comic:1');

    expect(writer.calls, hasLength(1));
    expect(writer.calls.single.module, LibraryModuleKey.comic);
    expect(writer.calls.single.workIds, <String>{'comic:1'});
    expect(writer.calls.single.isRead, isFalse);
  });

  test('downloadAll delegates to BulkDownloadUseCase when injected', () async {
    final bulkDownloadUseCase = _RecordingBulkDownloadUseCase();
    final adapter = ComicDetailAdapter(
      _FakeComicRepository(),
      bulkDownloadUseCase: bulkDownloadUseCase,
      stateRepository: _FakeLibraryStateRepository(),
    );

    await adapter.downloadAll(workId: 'comic:1');

    expect(bulkDownloadUseCase.requestedComicIds, <Set<String>>[
      <String>{'comic:1'},
    ]);
  });

  test('downloadUnread keeps per-episode fallback behavior', () async {
    final stateRepository = _RecordingLibraryStateRepository(
      episodeStates: <String, LibraryEpisodeState>{
        'comic:1:120': LibraryEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: 'comic:1:120',
          workId: 'comic:1',
          isRead: true,
        ),
      },
    );
    final adapter = ComicDetailAdapter(
      _FakeComicRepository(),
      stateRepository: stateRepository,
    );

    await adapter.downloadUnread(workId: 'comic:1');

    expect(stateRepository.downloadedEpisodeIds, <String>['comic:1:90']);
  });

  test('loadChapters maps current reading progress to chapter progress info', () async {
    final repository = _FakeComicRepository(
      progress: ComicReadingProgress(
        comicId: 'comic:1',
        episodeId: 'comic:1:90',
        imageIndex: 2,
        scrollOffset: 120,
        updatedAt: DateTime(2026, 5, 12),
      ),
      imageCountByEpisodeId: const <String, int>{'comic:1:90': 5},
    );
    final adapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final chapters = await adapter.loadChapters(
      workId: 'comic:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );
    final current = chapters.singleWhere((chapter) => chapter.episodeId == 'comic:1:90');

    expect(current.progressInfo?.label, '第 3 页');
    expect(current.progressInfo?.isCurrent, isTrue);
    expect(current.progressInfo?.fraction, closeTo(3 / 5, 0.0001));
  });

  test('loadChapters clamps comic progress and hides it for read chapters', () async {
    final repository = _FakeComicRepository(
      progress: ComicReadingProgress(
        comicId: 'comic:1',
        episodeId: 'comic:1:90',
        imageIndex: 99,
        scrollOffset: 120,
        updatedAt: DateTime(2026, 5, 12),
      ),
      imageCountByEpisodeId: const <String, int>{'comic:1:90': 5},
    );
    final adapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(
        episodeStates: <String, LibraryEpisodeState>{
          'comic:1:120': LibraryEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic:1:120',
            workId: 'comic:1',
            isRead: false,
          ),
        },
      ),
    );

    final chapters = await adapter.loadChapters(
      workId: 'comic:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );
    final current = chapters.singleWhere((chapter) => chapter.episodeId == 'comic:1:90');

    expect(current.progressInfo?.label, '第 5 页');
    expect(current.progressInfo?.fraction, 1);

    final readAdapter = ComicDetailAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(
        episodeStates: <String, LibraryEpisodeState>{
          'comic:1:90': LibraryEpisodeState(
            moduleKey: LibraryModuleKey.comic,
            episodeId: 'comic:1:90',
            workId: 'comic:1',
            isRead: true,
          ),
        },
      ),
    );
    final readChapters = await readAdapter.loadChapters(
      workId: 'comic:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );

    expect(
      readChapters.singleWhere((chapter) => chapter.episodeId == 'comic:1:90').progressInfo,
      isNull,
    );
  });

  test('loadChapters ignores comic progress for missing episode', () async {
    final adapter = ComicDetailAdapter(
      _FakeComicRepository(
        progress: ComicReadingProgress(
          comicId: 'comic:1',
          episodeId: 'missing',
          imageIndex: 1,
          scrollOffset: 120,
          updatedAt: DateTime(2026, 5, 12),
        ),
      ),
      stateRepository: _FakeLibraryStateRepository(),
    );

    final chapters = await adapter.loadChapters(
      workId: 'comic:1',
      filters: const LibraryFilterSet(),
      sortOption: LibraryChapterSortOption.defaults,
    );

    expect(chapters.where((chapter) => chapter.progressInfo != null), isEmpty);
  });
}

class _FakeComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  _FakeComicEpisodeRefreshService({
    ComicEpisodeRefreshOutcome? catalogOutcome,
    ComicEpisodeRefreshOutcome? searchOutcome,
  })  : _catalogOutcome = catalogOutcome,
        _searchOutcome = searchOutcome;

  String? requestedTid;
  ComicEpisodeRefreshRequest? lastRequest;
  int catalogOnlyCalls = 0;
  int fetchEpisodeLinksCalls = 0;
  int searchAndCurrentOnlyCalls = 0;
  final ComicEpisodeRefreshOutcome? _catalogOutcome;
  final ComicEpisodeRefreshOutcome? _searchOutcome;

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    fetchEpisodeLinksCalls++;
    lastRequest = request;
    requestedTid = request.sourceTid;
    return const [
      ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
      ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
    ];
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    lastRequest = request;
    requestedTid = request.sourceTid;
    final catalog = await fetchCatalogOnly(request);
    if (catalog.catalogMatched && catalog.hasLinks) {
      return catalog;
    }
    return fetchSearchAndCurrentOnly(request);
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
  }
  ) async {
    catalogOnlyCalls++;
    lastRequest = request;
    requestedTid = request.sourceTid;
    final outcome = _catalogOutcome;
    if (outcome != null) {
      return outcome;
    }
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.catalog,
      links: [
        ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
        ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
      ],
      catalogMatched: true,
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
  }
  ) async {
    searchAndCurrentOnlyCalls++;
    lastRequest = request;
    requestedTid = request.sourceTid;
    final outcome = _searchOutcome;
    if (outcome != null) {
      return outcome;
    }
    final links = await fetchEpisodeLinks(request);
    return ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.search,
      links: links,
      usedSearch: true,
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return fetchEpisodeLinks(ComicEpisodeRefreshRequest(sourceTid: tid));
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(
    String catalogUrl, {
    FavoriteSyncExecutionContext? executionContext,
  }
  ) async {
    return ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.catalog,
      links: const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
        ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
      ],
      catalogMatched: true,
      catalogUrl: catalogUrl,
    );
  }
}

class _RecordingRefreshOutcomeApplier implements ComicRefreshOutcomeApplier {
  final List<ComicRefreshApplyRequest> requests = <ComicRefreshApplyRequest>[];

  @override
  Future<ComicRefreshApplyResult> apply(
    ComicRefreshApplyRequest request,
  ) async {
    requests.add(request);
    return ComicRefreshApplyResult(
      status: ComicRefreshApplyStatus.applied,
      insertedCount: request.links.length,
      updatedCount: 0,
      totalCount: request.links.length,
      coverPromoted: false,
    );
  }
}

class _RecordingSearchQueue implements ComicSearchRefreshQueueEnqueuer {
  final List<ComicEpisodeRefreshRequest> enqueuedRequests =
      <ComicEpisodeRefreshRequest>[];
  final List<String> enqueuedTitles = <String>[];
  final List<ComicSearchRefreshOrigin> enqueuedOrigins =
      <ComicSearchRefreshOrigin>[];

  @override
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
  }) async {
    enqueuedRequests.add(request);
    enqueuedTitles.add(title);
    enqueuedOrigins.add(origin);
    return ComicSearchRefreshEnqueueResult(
      entry: ComicSearchRefreshQueueEntry(
        id: enqueuedRequests.length,
        comicId: request.comicId ?? '',
        title: title,
        request: request,
        origin: origin,
        status: ComicSearchRefreshQueueStatus.pending,
        attempts: 0,
        availableAt: DateTime(2026, 5, 16),
        createdAt: DateTime(2026, 5, 16),
        updatedAt: DateTime(2026, 5, 16),
      ),
      position: 2,
      estimatedDuration: const Duration(seconds: 21),
      deduplicated: false,
    );
  }
}

class _FakeComicRepository implements ComicRepository {
  _FakeComicRepository({
    this.progress,
    this.title = 'Test Comic',
    this.imageCountByEpisodeId = const <String, int>{},
    this.catalogUrl,
  });

  final ComicReadingProgress? progress;
  final String title;
  final Map<String, int> imageCountByEpisodeId;
  final String? catalogUrl;
  bool mergeCalled = false;
  List<ComicEpisodeLink> lastMergedLinks = const [];
  String? lastFallbackTid;

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      sourceTypeId: '398',
      sourceTagName: '韩国漫画',
      title: title,
      sourceTitle: 'Source Test Comic',
      customTitle: 'Custom Test Comic',
      author: 'Author A',
      sourceAuthor: 'Source Author',
      customAuthor: 'Custom Author',
      translationGroup: 'Group A',
      sourceTranslationGroup: 'Source Group',
      customTranslationGroup: 'Custom Group',
      customSearchTitle: 'Search Test Comic',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 0,
      catalogUrl: catalogUrl,
    );
  }

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    mergeCalled = true;
    lastMergedLinks = episodeLinks;
    lastFallbackTid = fallbackSourceTid;
    return const ComicEpisodeRefreshResult(insertedCount: 2, updatedCount: 0, totalCount: 2);
  }

  @override
  Future<void> addToShelf({required String comicId, required String tid, required String fid, String? sourceTypeId, String? sourceTagName, required String title, required ParsedComicPost parsedPost}) async {}
  @override
  Future<void> removeFromShelf({required String comicId}) async {}
  @override
  Future<void> purgeWork({required String comicId}) async {}
  @override
  Future<String> createCategory({required String name}) async => 'c1';
  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}
  @override
  Future<void> deleteCategory({required String categoryId}) async {}
  @override
  Future<List<ComicShelfCategory>> getCategories() async => const [];
  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async => const ComicShelfDisplaySettings(gridColumnCount: 3);
  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    return const <ComicEpisodeItem>[
      ComicEpisodeItem(
        episodeId: 'comic:1:120',
        comicId: 'comic:1',
        episodeTitle: '后续',
        sourceTid: '120',
        sourceUrl: 'thread-120-1-1.html',
        orderIndex: 0,
        publishTimeText: null,
      ),
      ComicEpisodeItem(
        episodeId: 'comic:1:90',
        comicId: 'comic:1',
        episodeTitle: '首话',
        sourceTid: '90',
        sourceUrl: 'thread-90-1-1.html',
        orderIndex: 1,
        publishTimeText: null,
      ),
    ];
  }
  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    final imageCount = imageCountByEpisodeId[episodeId] ?? 1;
    return List<ComicEpisodeImageItem>.generate(
      imageCount,
      (index) => ComicEpisodeImageItem(
        episodeId: episodeId,
        imageUrl: episodeId.endsWith(':90')
            ? 'https://img.test/90-${index + 1}.jpg'
            : 'https://img.test/120-${index + 1}.jpg',
        imageIndex: index,
        cacheStatus: 'none',
      ),
    );
  }
  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => progress;
  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const [];
  @override
  Future<bool> isInShelf({required String comicId}) async => true;
  @override
  Future<void> moveComicToCategory({required String comicId, required String fromCategoryId, required String toCategoryId}) async {}
  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}
  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}
  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}
  @override
  Future<void> updateCustomCoverFromLocalFile({required String comicId, required String localCoverPath, String? sourceEpisodeId, int? sourceImageIndex, String? sourceImageUrl}) async {}
  @override
  Future<void> updateCustomMetadata({required String comicId, String? customTitle, String? customAuthor, String? customTranslationGroup, String? customSearchTitle}) async {}
  @override
  Future<void> clearCustomMetadata({required String comicId, bool title = false, bool author = false, bool translationGroup = false, bool searchTitle = false}) async {}
  @override
  Future<void> updateEpisodeImageCacheStatus({required String episodeId, required String imageUrl, required String cacheStatus, String? cacheLocalPath}) async {}
  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}
  @override
  Future<void> updateLastReadProgress({required String comicId, required String episodeId, required int imageIndex, required double scrollOffset}) async {}
  @override
  Future<void> updateCatalogUrl({required String comicId, required String catalogUrl}) async {}

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async => <String>{};
}

class _FakeComicRepositoryWithCoverWriter extends _FakeComicRepository
    implements ComicCoverCacheWriter {
  _FakeComicRepositoryWithCoverWriter({this.customCoverImageUrl});

  final String? customCoverImageUrl;
  String? lastCoverImageUrl;
  String? lastCoverLocalPath;
  String? lastCustomCoverLocalPath;

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    final detail = await super.getComicDetail(comicId: comicId);
    if (detail == null) {
      return null;
    }
    return ComicDetail(
      comicId: detail.comicId,
      sourceTid: detail.sourceTid,
      sourceFid: detail.sourceFid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      title: detail.title,
      sourceTitle: detail.sourceTitle,
      customTitle: detail.customTitle,
      author: detail.author,
      sourceAuthor: detail.sourceAuthor,
      customAuthor: detail.customAuthor,
      translationGroup: detail.translationGroup,
      sourceTranslationGroup: detail.sourceTranslationGroup,
      customTranslationGroup: detail.customTranslationGroup,
      customSearchTitle: detail.customSearchTitle,
      coverImageUrl: customCoverImageUrl ?? detail.coverImageUrl,
      customCoverImageUrl: customCoverImageUrl,
      coverLocalPath: detail.coverLocalPath,
      customCoverLocalPath: detail.customCoverLocalPath,
      updatedAt: detail.updatedAt,
      episodeCount: detail.episodeCount,
    );
  }

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCoverImageUrl = coverImageUrl;
    lastCoverLocalPath = coverLocalPath;
    lastCustomCoverLocalPath = customCoverLocalPath;
  }
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    lastRequest = request;
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
  _FakeLibraryStateRepository({
    this.workState,
    this.episodeStates = const <String, LibraryEpisodeState>{},
  });

  final LibraryWorkState? workState;
  final Map<String, LibraryEpisodeState> episodeStates;

  @override
  Future<void> bindTagToWork({required LibraryModuleKey moduleKey, required String workId, required String tagId}) async {}
  @override
  Future<int> countDownloadedEpisodes({required LibraryModuleKey moduleKey, required String workId}) async => 0;
  @override
  Future<int> countReadEpisodes({required LibraryModuleKey moduleKey, required String workId}) async => 0;
  @override
  Future<int> countUnreadEpisodes({required LibraryModuleKey moduleKey, required String workId}) async => 0;
  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}
  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}
  @override
  Future<String> createTag({required String name}) async => 't1';
  @override
  Future<void> deleteTag({required String tagId}) async {}
  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({required LibraryModuleKey moduleKey, required LibraryDisplayMode defaultDisplayMode}) async =>
      LibraryModuleDisplaySettings(moduleKey: moduleKey, displayMode: defaultDisplayMode, gridColumns: 3, updatedAt: DateTime(2026, 1, 1));
  @override
  Future<LibraryEpisodeState?> getEpisodeState({required LibraryModuleKey moduleKey, required String episodeId}) async => episodeStates[episodeId];
  @override
  Future<List<LibraryTag>> getTags() async => const [];
  @override
  Future<LibraryWorkState?> getWorkState({required LibraryModuleKey moduleKey, required String workId}) async => workState;
  @override
  Future<List<LibraryTag>> getWorkTags({required LibraryModuleKey moduleKey, required String workId}) async => const [];
  @override
  Future<bool> hasAnyTag({required LibraryModuleKey moduleKey, required String workId}) async => false;
  @override
  Future<void> renameTag({required String tagId, required String newName}) async {}
  @override
  Future<void> unbindTagFromWork({required LibraryModuleKey moduleKey, required String workId, required String tagId}) async {}
  @override
  Future<void> upsertDisplaySettings({required LibraryModuleKey moduleKey, required LibraryDisplayMode displayMode, required int gridColumns}) async {}
  @override
  Future<void> upsertEpisodeState({required LibraryModuleKey moduleKey, required String episodeId, required String workId, bool? isRead, bool? isDownloaded, bool? isBookmarked, DateTime? readAt, DateTime? downloadedAt}) async {}
  @override
  Future<void> upsertWorkState({required LibraryModuleKey moduleKey, required String workId, String? lastReadEpisodeId, DateTime? lastReadAt, DateTime? checkUpdatedAt, DateTime? fetchedUpdatedAt, String? introText}) async {}
}

class _RecordingLibraryStateRepository extends _FakeLibraryStateRepository {
  _RecordingLibraryStateRepository({
    super.episodeStates,
  });

  final List<String> downloadedEpisodeIds = <String>[];

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
    if (isDownloaded == true) {
      downloadedEpisodeIds.add(episodeId);
    }
  }
}

class _RecordingReadingStateBatchWriter implements ReadingStateBatchWriter {
  final List<_ReadingStateBatchCall> calls = <_ReadingStateBatchCall>[];

  @override
  Future<void> setWorkRead({
    required LibraryModuleKey module,
    required String workId,
    required bool isRead,
  }) async {
    calls.add(
      _ReadingStateBatchCall(
        module: module,
        workIds: <String>{workId},
        isRead: isRead,
      ),
    );
  }

  @override
  Future<void> setWorksRead({
    required LibraryModuleKey module,
    required Set<String> workIds,
    required bool isRead,
  }) async {
    calls.add(
      _ReadingStateBatchCall(
        module: module,
        workIds: workIds,
        isRead: isRead,
      ),
    );
  }
}

class _ReadingStateBatchCall {
  const _ReadingStateBatchCall({
    required this.module,
    required this.workIds,
    required this.isRead,
  });

  final LibraryModuleKey module;
  final Set<String> workIds;
  final bool isRead;
}

class _RecordingBulkDownloadUseCase implements BulkDownloadUseCase {
  final List<Set<String>> requestedComicIds = <Set<String>>[];

  @override
  Future<BulkDownloadResult> downloadComics(Set<String> comicIds) async {
    requestedComicIds.add(Set<String>.from(comicIds));
    return BulkDownloadResult(
      requestedComicIds: comicIds.toList(growable: false),
      completedComicIds: comicIds.toList(growable: false),
      failedComicIds: const <String>[],
      downloadedEpisodeCount: 0,
    );
  }
}

class _FakeDiscoveryService extends ComicEpisodeDiscoveryService {
  _FakeDiscoveryService({this.threadResult})
      : super(
          fetchThreadDetail: (_) async => throw UnimplementedError(),
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
          catalogHtmlFetcher: _FakeCatalogHtmlFetcher(),
        );

  final ParsedThreadResult? threadResult;
  int fetchAndParseThreadCalls = 0;

  @override
  Future<ParsedThreadResult?> fetchAndParseThread(String tid) async {
    fetchAndParseThreadCalls++;
    return threadResult;
  }
}

class _FakeCatalogHtmlFetcher implements CatalogHtmlFetcher {
  @override
  Future<String?> fetchHtml(String url) async => null;
}

class _FakeIncrementalDiscovery extends ComicIncrementalEpisodeDiscovery {
  _FakeIncrementalDiscovery({
    this.directResult = const <ComicEpisodeLink>[],
  }) : super(
          fetchThreadDetail: (_) async => throw UnimplementedError(),
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        );

  final List<ComicEpisodeLink> directResult;

  @override
  List<ComicEpisodeLink> discoverDirectIncremental({
    required List<ComicEpisodeLink> currentLinks,
    required Set<String> knownTids,
  }) {
    return directResult;
  }

  @override
  Future<List<ComicEpisodeLink>> discoverRecursiveIncremental({
    required String startTid,
    required Set<String> knownTids,
  }) async {
    return const <ComicEpisodeLink>[];
  }
}
