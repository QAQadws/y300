import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/presentation/adapters/novel_shelf_adapter.dart';

void main() {
  test('NovelShelfAdapter returns metadata before cover warmup', () async {
    final repository = _FakeNovelRepository(
      shelfItems: <NovelItem>[
        NovelItem(
          novelId: 'novel-1',
          sourceTid: '100',
          sourceFid: '49',
          title: '小说A',
          author: '作者A',
          coverImageUrl: 'https://img.test/novel-1.jpg',
          updatedAt: DateTime(2026, 1, 1),
          episodeCount: 2,
        ),
      ],
    );
    final cache = _FakeImageCacheService(localPath: '/cache/novel-1.jpg');
    final adapter = NovelShelfAdapter(
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

    expect(result?.coverLocalPath, '/cache/novel-1.jpg');
    expect(cache.lastRequest?.cacheKey, 'cover/novel/novel-1');
    expect(repository.lastCoverLocalPath, '/cache/novel-1.jpg');
  });

  test('NovelShelfAdapter exposes novel progress from task progress hub', () {
    final hub = DefaultLibraryTaskProgressHub();
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '小说刷新中',
        source: LibraryMutationSource.novelRefresh,
      ),
    );
    final registration = hub.registerSource(
      modules: const <LibraryModuleKey>{LibraryModuleKey.novel},
      progress: progress,
    );
    addTearDown(progress.dispose);
    addTearDown(registration.dispose);
    addTearDown(hub.dispose);
    final adapter = NovelShelfAdapter(
      _FakeNovelRepository(shelfItems: const <NovelItem>[]),
      stateRepository: _FakeLibraryStateRepository(),
      taskProgressHub: hub,
    );

    expect(adapter.taskProgress?.value?.message, '小说刷新中');
    expect(
      adapter.taskProgress?.value?.source,
      LibraryMutationSource.novelRefresh,
    );
  });
}

class _FakeNovelRepository implements NovelRepository, NovelCoverCacheWriter {
  _FakeNovelRepository({required this.shelfItems});

  final List<NovelItem> shelfItems;
  String? lastCoverLocalPath;

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
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async => const <NovelEpisodeItem>[];

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async => NovelReaderPreferences.defaults();

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async => shelfItems;

  @override
  Future<void> moveNovelToCategory({required String novelId, required String fromCategoryId, required String toCategoryId}) async {}

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveReadingProgress({required String novelId, required String episodeId, required double scrollOffset}) async {}

  @override
  Future<void> updateCoverCache({
    required String novelId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastCoverLocalPath = coverLocalPath ?? customCoverLocalPath;
  }

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
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
