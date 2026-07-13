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

    expect(current.progressInfo?.label, '第 3 页');
    expect(current.progressInfo?.fraction, 0.35);
    expect(current.progressInfo?.isCurrent, isTrue);
  });

  test('loadChapters maps vertical novel progress to percent label', () async {
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

    expect(current.progressInfo?.label, '已读 42%');
    expect(current.progressInfo?.fraction, 0.42);
  });

  test(
    'loadChapters shows reading fallback and hides progress for read chapter',
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

      expect(chapters.first.progressInfo?.label, '阅读中');

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

      expect(readChapters.first.progressInfo, isNull);
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
      expect(header.sourceAuthor, 'Novel Author');
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

  test('loadHeader exposes source author id and source intro', () async {
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

    expect(header.sourceAuthorId, '406769');
    expect(header.intro, '来源简介');
  });
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
  _FakeNovelRepository({this.progress, this.coverImageUrl});

  final NovelReadingProgress? progress;
  final String? coverImageUrl;

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
      coverImageUrl: coverImageUrl,
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
        sourcePid: '1',
        episodeTitle: '第一章',
        orderIndex: 0,
      ),
      NovelEpisodeItem(
        episodeId: '$novelId:2',
        novelId: novelId,
        sourceTid: '100',
        sourcePid: '2',
        episodeTitle: '第二章',
        orderIndex: 1,
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

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;

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
