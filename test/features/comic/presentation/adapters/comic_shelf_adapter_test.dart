import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/presentation/adapters/comic_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

void main() {
  test('ComicShelfAdapter returns metadata before cover warmup', () async {
    final repository = _FakeComicRepository(
      shelfItems: <ComicShelfItem>[
        ComicShelfItem(
          comicId: 'comic-1',
          title: '漫画A',
          author: '作者A',
          coverImageUrl: 'https://img.test/comic-1.jpg',
          categoryId: 'default',
          addedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final cache = _FakeImageCacheService(localPath: '/cache/comic-1.jpg');
    final adapter = ComicShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: cache,
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.coverLocalPath, isNull);
    expect(cache.lastRequest, isNull);

    final requests = await adapter.buildCoverWarmupRequests(
      selectedCategoryId: 'default',
      itemsByCategory: <String, List<LibraryWorkItem>>{'default': items},
    );
    final result = await adapter.warmCover(requests.single);

    expect(result?.coverLocalPath, '/cache/comic-1.jpg');
    expect(cache.lastRequest?.cacheKey, 'cover/comic/comic-1');
    expect(repository.lastCoverLocalPath, '/cache/comic-1.jpg');
  });

  test('ComicShelfAdapter does not expose old ordinary local cover while custom cover is pending', () async {
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(
        shelfItems: <ComicShelfItem>[
          ComicShelfItem(
            comicId: 'comic-2',
            title: '漫画B',
            author: '作者B',
            coverImageUrl: 'https://img.test/ordinary.jpg',
            customCoverImageUrl: 'https://img.test/custom.jpg',
            coverLocalPath: '/cache/old-ordinary.jpg',
            categoryId: 'default',
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: _FakeImageCacheService(localPath: '/cache/custom.jpg'),
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.coverLocalPath, isNull);
    expect(items.single.customCoverLocalPath, isNull);
    final requests = await adapter.buildCoverWarmupRequests(
      selectedCategoryId: 'default',
      itemsByCategory: <String, List<LibraryWorkItem>>{'default': items},
    );
    expect(requests.single.role, ImageCacheRole.customCover);
    expect(requests.single.cacheKey, 'cover/custom/comic/comic-2');
  });

  test('custom metadata flag hides custom cover from shelf item mapping', () async {
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(
        shelfItems: <ComicShelfItem>[
          ComicShelfItem(
            comicId: 'comic-2',
            title: '自定义标题',
            sourceTitle: '来源标题',
            author: '自定义作者',
            sourceAuthor: '来源作者',
            translationGroup: '自定义组',
            sourceTranslationGroup: '来源组',
            coverImageUrl: 'https://img.test/ordinary.jpg',
            customCoverImageUrl: 'https://img.test/custom.jpg',
            coverLocalPath: '/cache/old-ordinary.jpg',
            customCoverLocalPath: '/cache/custom.jpg',
            categoryId: 'default',
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: _FakeImageCacheService(localPath: '/cache/custom.jpg'),
      featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
        readerCustomMetadataEnabled: false,
      ),
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.coverLocalPath, '/cache/old-ordinary.jpg');
    expect(items.single.title, '来源标题');
    expect(items.single.secondaryName, '来源作者 / 来源组');
    expect(items.single.customCoverImageUrl, isNull);
    expect(items.single.customCoverLocalPath, isNull);
  });

  test('custom metadata flag bypasses composed snapshot fields', () async {
    final repository = _FakeSnapshotComicRepository(
      shelfItems: <ComicShelfItem>[
        ComicShelfItem(
          comicId: 'comic-4',
          title: '自定义标题',
          sourceTitle: '来源标题',
          author: '自定义作者',
          sourceAuthor: '来源作者',
          translationGroup: '自定义组',
          sourceTranslationGroup: '来源组',
          coverImageUrl: 'https://img.test/custom.jpg',
          customCoverImageUrl: 'https://img.test/custom.jpg',
          coverLocalPath: '/cache/custom.jpg',
          customCoverLocalPath: '/cache/custom.jpg',
          categoryId: 'default',
          addedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final adapter = ComicShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
      featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
        readerCustomMetadataEnabled: false,
      ),
    );

    final snapshot = await adapter.querySnapshot(
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: '',
    );
    final item = snapshot.itemsByCategory['default']!.single;

    expect(repository.snapshotQueryCount, 0);
    expect(snapshot.visibleMatchCountByCategory['default'], 1);
    expect(item.title, '来源标题');
    expect(item.secondaryName, '来源作者 / 来源组');
    expect(item.coverImageUrl, isNull);
    expect(item.coverLocalPath, isNull);
    expect(item.customCoverImageUrl, isNull);
    expect(item.customCoverLocalPath, isNull);
  });

  test('ComicShelfAdapter fallback uses repository stats for missing state rows', () async {
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(
        shelfItems: <ComicShelfItem>[
          ComicShelfItem(
            comicId: 'comic-3',
            title: '漫画C',
            author: '作者C',
            coverImageUrl: null,
            categoryId: 'default',
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
        statsByComicId: const <String, ComicShelfWorkStats>{
          'comic-3': ComicShelfWorkStats(
            totalCount: 3,
            unreadCount: 2,
            readCount: 1,
            downloadedCount: 1,
          ),
        },
      ),
      stateRepository: _FakeLibraryStateRepository(),
    );

    final items = await adapter.loadCategoryItems(categoryId: 'default');

    expect(items.single.totalChapterCount, 3);
    expect(items.single.unreadCount, 2);
    expect(items.single.readChapterCount, 1);
    expect(items.single.isDownloaded, isTrue);
  });

  test('ComicShelfAdapter exposes merge duplicates module action', () async {
    final repository = _FakeDuplicateComicRepository(
      mergeResult: const ComicDuplicateMergeResult(
        targetComicId: 'comic-a',
        targetTitle: '短标题',
        mergedComicIds: <String>{'comic-b'},
        replacements: <String, String>{'comic-b': 'comic-a'},
        movedEpisodeCount: 2,
      ),
    );
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final adapter = ComicShelfAdapter(
      repository,
      stateRepository: _FakeLibraryStateRepository(),
      duplicateMergeService: ComicDuplicateMergeService(repository: repository),
      shelfRefreshBus: bus,
    );

    final result = await adapter.runMenuAction('merge-duplicates');

    expect(adapter.menuActions.single.label, '合并重复');
    expect(result.changed, isTrue);
    expect(result.message, '已合并 1 个重复漫画');
    expect(repository.mergeAllCallCount, 1);
    expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
    expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
    expect(bus.signal.value?.source, LibraryMutationSource.duplicateMerge);
    expect(bus.signal.value?.payload['removedComicCount'], 1);
  });

  test('ComicShelfAdapter exposes comic progress from task progress hub', () {
    final hub = DefaultLibraryTaskProgressHub();
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '漫画队列处理中',
        source: LibraryMutationSource.comicSearchQueue,
      ),
    );
    final registration = hub.registerSource(
      modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
      progress: progress,
    );
    addTearDown(progress.dispose);
    addTearDown(registration.dispose);
    addTearDown(hub.dispose);
    final adapter = ComicShelfAdapter(
      _FakeComicRepository(shelfItems: const <ComicShelfItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      taskProgressHub: hub,
    );

    expect(adapter.taskProgress?.value?.message, '漫画队列处理中');
    expect(
      adapter.taskProgress?.value?.source,
      LibraryMutationSource.comicSearchQueue,
    );
  });
}

class _FakeSnapshotComicRepository extends _FakeComicRepository
    implements ComicShelfSnapshotRepository {
  _FakeSnapshotComicRepository({
    required super.shelfItems,
  });

  int snapshotQueryCount = 0;

  @override
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    snapshotQueryCount++;
    return LibraryShelfSnapshot(
      categories: (await getCategories()).map((category) {
        return LibraryCategory(
          categoryId: category.categoryId,
          name: category.name,
          sortOrder: category.sortOrder,
          createdAt: category.createdAt,
        );
      }).toList(growable: false),
      itemsByCategory: <String, List<LibraryWorkItem>>{
        'default': <LibraryWorkItem>[
          LibraryWorkItem(
            workId: 'snapshot-work',
            categoryId: 'default',
            title: 'Snapshot Custom',
            customCoverImageUrl: 'https://img.test/snapshot-custom.jpg',
            customCoverLocalPath: '/cache/snapshot-custom.jpg',
            unreadCount: 0,
            totalChapterCount: 0,
            readChapterCount: 0,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      },
      visibleMatchCountByCategory: const <String, int>{'default': 1},
    );
  }
}

class _FakeComicRepository
    implements ComicRepository, ComicShelfStatsRepository, ComicCoverCacheWriter {
  _FakeComicRepository({
    required this.shelfItems,
    this.statsByComicId = const <String, ComicShelfWorkStats>{},
  });

  final List<ComicShelfItem> shelfItems;
  final Map<String, ComicShelfWorkStats> statsByComicId;
  String? lastCoverLocalPath;

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    return <ComicShelfCategory>[
      ComicShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async => const [];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async => const ComicShelfDisplaySettings(gridColumnCount: 3);

  @override
  Future<ComicShelfWorkStats> getShelfWorkStats({required String comicId}) async {
    return statsByComicId[comicId] ??
        const ComicShelfWorkStats(
          totalCount: 0,
          unreadCount: 0,
          readCount: 0,
          downloadedCount: 0,
        );
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async => const [];

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => shelfItems;

  @override
  Future<bool> isInShelf({required String comicId}) async => true;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> moveComicToCategory({required String comicId, required String fromCategoryId, required String toCategoryId}) async {}

  @override
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCoverLocalPath = coverLocalPath ?? customCoverLocalPath;
  }

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

  @override
  Future<void> updateCustomCoverFromLocalFile({required String comicId, required String localCoverPath, String? sourceEpisodeId, int? sourceImageIndex, String? sourceImageUrl}) async {}

  @override
  Future<void> updateCustomMetadata({required String comicId, String? customTitle, String? customAuthor, String? customTranslationGroup, String? customSearchTitle}) async {}

  @override
  Future<void> clearCustomMetadata({required String comicId, bool title = false, bool author = false, bool translationGroup = false, bool searchTitle = false}) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {}

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}
}

class _FakeDuplicateComicRepository extends _FakeComicRepository
    implements ComicDuplicateMergeRepository {
  _FakeDuplicateComicRepository({
    required this.mergeResult,
  }) : super(shelfItems: const <ComicShelfItem>[]);

  final ComicDuplicateMergeResult mergeResult;
  int mergeAllCallCount = 0;

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) async {
    if (mergeAllCallCount > 0) {
      return const <ComicDuplicateGroup>[];
    }
    return <ComicDuplicateGroup>[
      ComicDuplicateGroup(
        comicIds: <String>{mergeResult.targetComicId, ...mergeResult.mergedComicIds},
        sharedTids: const <String>{'100'},
      ),
    ];
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    mergeAllCallCount++;
    return mergeResult;
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
  Future<CachedImageResult> copyProtectedLocalFile(ImageCacheLocalCopyRequest request) async => CachedImageResult.failed;

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
  Future<String> createTag({required String name}) async => 'tag-1';
  @override
  Future<void> deleteTag({required String tagId}) async {}
  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({required LibraryModuleKey moduleKey, required LibraryDisplayMode defaultDisplayMode}) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }
  @override
  Future<LibraryEpisodeState?> getEpisodeState({required LibraryModuleKey moduleKey, required String episodeId}) async => null;
  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];
  @override
  Future<LibraryWorkState?> getWorkState({required LibraryModuleKey moduleKey, required String workId}) async => null;
  @override
  Future<List<LibraryTag>> getWorkTags({required LibraryModuleKey moduleKey, required String workId}) async => const <LibraryTag>[];
  @override
  Future<bool> hasAnyTag({required LibraryModuleKey moduleKey, required String workId}) async => false;
  @override
  Future<void> renameTag({required String tagId, required String newName}) async {}
  @override
  Future<void> unbindTagFromWork({required LibraryModuleKey moduleKey, required String workId, required String tagId}) async {}
  @override
  Future<void> upsertDisplaySettings({required LibraryModuleKey moduleKey, required LibraryDisplayMode displayMode, required int gridColumns}) async {}
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
  }) async {}
}
