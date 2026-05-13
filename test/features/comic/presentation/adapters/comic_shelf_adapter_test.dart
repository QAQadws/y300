import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/adapters/comic_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';

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

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {}

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
