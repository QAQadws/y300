import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/presentation/adapters/comic_detail_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';

void main() {
  test('refreshWork delegates to comic domain refresh service and merges episodes', () async {
    final repository = _FakeComicRepository();
    final refreshService = _FakeComicEpisodeRefreshService();
    final adapter = ComicDetailAdapter(
      repository,
      refreshService: refreshService,
      stateRepository: _FakeLibraryStateRepository(),
    );

    await adapter.refreshWork(workId: 'comic:1');

    expect(refreshService.requestedTid, '100');
    expect(refreshService.lastRequest?.customSearchTitle, 'Search Test Comic');
    expect(repository.mergeCalled, isTrue);
    expect(repository.lastMergedLinks.length, 2);
    expect(repository.lastFallbackTid, '100');
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
}

class _FakeComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  String? requestedTid;
  ComicEpisodeRefreshRequest? lastRequest;

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    lastRequest = request;
    requestedTid = request.sourceTid;
    return const [
      ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
      ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
    ];
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return fetchEpisodeLinks(ComicEpisodeRefreshRequest(sourceTid: tid));
  }
}

class _FakeComicRepository implements ComicRepository {
  _FakeComicRepository({this.progress});

  final ComicReadingProgress? progress;
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
      title: 'Test Comic',
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
    return <ComicEpisodeImageItem>[
      ComicEpisodeImageItem(
        episodeId: episodeId,
        imageUrl: episodeId.endsWith(':90')
            ? 'https://img.test/90-1.jpg'
            : 'https://img.test/120-1.jpg',
        imageIndex: 0,
        cacheStatus: 'none',
      ),
    ];
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
