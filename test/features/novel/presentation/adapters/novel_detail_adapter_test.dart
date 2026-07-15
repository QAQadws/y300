import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/presentation/adapters/novel_detail_adapter.dart';

void main() {
  test(
    'clearAllReadState delegates to ReadingStateBatchWriter when injected',
    () async {
      final writer = _RecordingReadingStateBatchWriter();
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        readingStateBatchWriter: writer,
        stateRepository: _RecordingLibraryStateRepository(),
      );

      await adapter.clearAllReadState(workId: 'novel:1');

      expect(writer.calls, hasLength(1));
      expect(writer.calls.single.module, LibraryModuleKey.novel);
      expect(writer.calls.single.workIds, <String>{'novel:1'});
      expect(writer.calls.single.isRead, isFalse);
    },
  );

  test(
    'clearAllReadState keeps fallback per-episode loop without writer',
    () async {
      final stateRepository = _RecordingLibraryStateRepository();
      final adapter = NovelDetailAdapter(
        _FakeNovelRepository(),
        stateRepository: stateRepository,
      );

      await adapter.clearAllReadState(workId: 'novel:1');

      expect(stateRepository.unreadEpisodeIds, <String>[
        'novel:1:1',
        'novel:1:2',
      ]);
    },
  );

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

  test('loadChapters maps paged novel progress to page label', () async {
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

    expect(current.progressInfo?.label, '上次阅读');
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

    expect(current.progressInfo?.label, '上次阅读');
    expect(current.progressInfo?.fraction, 0.42);
  });

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
            ?.label,
        '上次阅读',
      );

      final readAdapter = NovelDetailAdapter(
        _FakeNovelRepository(progress: progress),
        stateRepository: _RecordingLibraryStateRepository(
          episodeStates: <String, LibraryEpisodeState>{
            'novel:1:1': LibraryEpisodeState(
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
            ?.label,
        '上次阅读',
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

    expect(updateService.novelIds, <String>['novel:1']);
    expect(result.message, '已新增 1 章，更新 2 章');
    expect(repository.lastRefreshMode, isNull);
  });

  test(
    'loadHeader caches remote cover as protected and writes local path',
    () async {
      final repository = _FakeNovelRepositoryWithCoverWriter(
        coverImageUrl: 'https://img.test/novel-cover.jpg',
      );
      final cacheService = _FakeImageCacheService(
        localPath: '/cache/novel-cover.jpg',
      );
      final adapter = NovelDetailAdapter(
        repository,
        imageCacheService: cacheService,
        stateRepository: _RecordingLibraryStateRepository(),
      );

      final header = await adapter.loadHeader(workId: 'novel:1');

      expect(header.coverLocalPath, '/cache/novel-cover.jpg');
      expect(header.sourceTitle, 'Novel');
      expect(header.sourceAuthor, isNull);
      expect(header.publisherName, 'Novel Author');
      expect(cacheService.lastRequest?.cacheKey, 'cover/novel/novel:1');
      expect(cacheService.lastRequest?.ownerType, ImageCacheOwnerType.novel);
      expect(cacheService.lastRequest?.role, ImageCacheRole.cover);
      expect(cacheService.lastRequest?.protected, isTrue);
      expect(
        cacheService.lastRequest?.effectiveRetentionClass,
        ImageRetentionClass.protected,
      );
      expect(repository.lastCoverImageUrl, 'https://img.test/novel-cover.jpg');
      expect(repository.lastCoverLocalPath, '/cache/novel-cover.jpg');
    },
  );

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
      final cacheService = _FakeImageCacheService(
        localPath: '/protected/custom-novel-cover.jpg',
      );
      final adapter = NovelDetailAdapter(
        repository,
        imageCacheService: cacheService,
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
      expect(
        repository.lastCustomCoverPath,
        '/protected/custom-novel-cover.jpg',
      );
      expect(repository.lastFocusX, -0.1);
      expect(repository.lastFocusY, 0.3);
      expect(repository.coverRemoved, isTrue);
      expect(
        cacheService.lastCopyRequest?.ownerType,
        ImageCacheOwnerType.novel,
      );
      expect(cacheService.lastCopyRequest?.role, ImageCacheRole.customCover);
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

  @override
  Future<NovelChapterSyncResult> update(String novelId) async {
    novelIds.add(novelId);
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

  /// 最近一次 refreshEpisodes 收到的 mode —— 用来断言 adapter 是否传了增量模式。
  NovelEpisodeRefreshMode? lastRefreshMode;

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
  Future<NovelReaderPreferences> getReaderPreferences() async =>
      NovelReaderPreferences.defaults();

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

  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    lastRefreshMode = mode;
    return const NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 0,
    );
  }

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
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {}

  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> upsertReaderPreferences(
    NovelReaderPreferences preferences,
  ) async {}

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
    implements NovelCustomMetadataWriter, NovelCustomCoverWriter {
  String? lastCustomTitle;
  String? lastCustomCoverPath;
  double? lastFocusX;
  double? lastFocusY;
  bool coverRemoved = false;

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

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;
  ImageCacheLocalCopyRequest? lastCopyRequest;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    lastCopyRequest = request;
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

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

class _RecordingLibraryStateRepository implements LibraryStateRepository {
  _RecordingLibraryStateRepository({
    this.episodeStates = const <String, LibraryEpisodeState>{},
  });

  final List<String> unreadEpisodeIds = <String>[];
  final Map<String, LibraryEpisodeState> episodeStates;
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
  }) async => episodeStates[episodeId];

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
  }) async {
    if (isRead == false) {
      unreadEpisodeIds.add(episodeId);
    }
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
      _ReadingStateBatchCall(module: module, workIds: workIds, isRead: isRead),
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
