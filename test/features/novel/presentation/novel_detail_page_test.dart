import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/services/novel_download_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  testWidgets(
    'NovelDetailPage renders unified detail header and chapter list',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
            novelDownloadServiceProvider.overrideWithValue(
              _NoopNovelDownloadService(),
            ),
            libraryStateRepositoryProvider.overrideWithValue(
              _FakeLibraryStateRepository(),
            ),
            novelSourceStateRepositoryProvider.overrideWithValue(
              const _EmptyNovelSourceStateRepository(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _NoopImageCacheService(),
            ),
          ],
          child: const MaterialApp(home: NovelDetailPage(novelId: 'novel:1')),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test Novel'), findsAtLeastNWidgets(1));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('unified-detail-chapter-novel:1:e1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-novel:1:e1')),
        findsOneWidget,
      );
      expect(find.textContaining('Pid:5001'), findsOneWidget);
      expect(find.byIcon(Icons.file_download), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('NovelDetailPage hides group row but keeps author row', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          novelDownloadServiceProvider.overrideWithValue(
            _NoopNovelDownloadService(),
          ),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          novelSourceStateRepositoryProvider.overrideWithValue(
            const _EmptyNovelSourceStateRepository(),
          ),
          imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
        ],
        child: const MaterialApp(home: NovelDetailPage(novelId: 'novel:1')),
      ),
    );

    await tester.pumpAndSettle();

    // 小说 detail 不展示「原作者作品」组（group_outlined）行。
    expect(find.byKey(const Key('unified-detail-group-row')), findsNothing);
    expect(find.byIcon(Icons.group_outlined), findsNothing);
    // 作者行（person_outlined）仍要保留。
    expect(find.byKey(const Key('unified-detail-author-row')), findsOneWidget);
    expect(find.byIcon(Icons.person_outlined), findsOneWidget);
  });

  testWidgets('metadata remains visible while first chapters hydrate', (
    tester,
  ) async {
    final sourceRepository = _HydrationNovelSourceStateRepository();
    final syncService = _ControlledNovelChapterSyncService();
    addTearDown(syncService.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          novelDownloadServiceProvider.overrideWithValue(
            _NoopNovelDownloadService(),
          ),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          novelSourceStateRepositoryProvider.overrideWithValue(
            sourceRepository,
          ),
          novelChapterSyncServiceProvider.overrideWithValue(syncService),
          imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
        ],
        child: const MaterialApp(home: NovelDetailPage(novelId: 'novel:1')),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Test Novel'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const Key('novel-chapter-hydration-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('正在加载第 1/2 页'), findsOneWidget);
    expect(syncService.request?.publisherId, '406769');
    expect(syncService.request?.mode, NovelChapterSyncMode.initialFull);

    syncService.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-chapter-hydration-panel')),
      findsNothing,
    );
  });
}

class _EmptyNovelSourceStateRepository implements NovelSourceStateRepository {
  const _EmptyNovelSourceStateRepository();

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    return _sourceState(
      novelId: novelId,
      hydrationState: NovelChapterHydrationState.ready,
    );
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

class _HydrationNovelSourceStateRepository
    implements NovelSourceStateRepository {
  NovelSourceState state = _sourceState(
    novelId: 'novel:1',
    hydrationState: NovelChapterHydrationState.metadataOnly,
  );

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    return state;
  }

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {}

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {}

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {}
}

class _ControlledNovelChapterSyncService implements NovelChapterSyncService {
  final StreamController<NovelChapterSyncProgress> _progress =
      StreamController<NovelChapterSyncProgress>.broadcast();
  final Completer<void> _completion = Completer<void>();
  NovelChapterSyncRequest? request;
  bool _active = false;

  @override
  bool hasActiveRun(String novelId) => _active;

  @override
  Future<NovelChapterSyncResult> synchronize(
    NovelChapterSyncRequest request,
  ) async {
    this.request = request;
    _active = true;
    _progress.add(
      NovelChapterSyncProgress(
        runId: 'widget-run',
        novelId: request.novelId,
        mode: request.mode,
        phase: NovelChapterSyncPhase.fetchingPage,
        currentPage: 1,
        totalPages: 2,
        acceptedCount: 1,
      ),
    );
    await _completion.future;
    _active = false;
    final checkpoint = NovelChapterSyncCheckpoint(
      novelId: request.novelId,
      publisherId: request.publisherId,
      lastCompletedAuthorPage: 2,
      lastSeenPid: '5001',
      completedAt: DateTime(2026, 7, 13),
    );
    _progress.add(
      NovelChapterSyncProgress(
        runId: 'widget-run',
        novelId: request.novelId,
        mode: request.mode,
        phase: NovelChapterSyncPhase.completed,
        currentPage: 2,
        totalPages: 2,
        acceptedCount: 1,
      ),
    );
    return NovelChapterSyncResult(
      mode: request.mode,
      fetchedPages: 2,
      insertedCount: 1,
      updatedCount: 0,
      totalCount: 1,
      checkpoint: checkpoint,
    );
  }

  @override
  Stream<NovelChapterSyncProgress> watchProgress(String novelId) {
    return _progress.stream;
  }

  void complete() => _completion.complete();

  Future<void> dispose() => _progress.close();
}

NovelSourceState _sourceState({
  required String novelId,
  required NovelChapterHydrationState hydrationState,
}) {
  return NovelSourceState(
    novelId: novelId,
    publisherId: '406769',
    publisherName: 'Author A',
    firstPostPid: '5000',
    sourceIntro: '来源简介',
    catalogEntries: const <NovelSourceCatalogEntry>[],
    metadataSourceVersion: 4,
    hydrationState: hydrationState,
    metadataIngestedAt: DateTime(2026, 7, 13),
    chaptersHydratedAt: hydrationState == NovelChapterHydrationState.ready
        ? DateTime(2026, 7, 13)
        : null,
    lastCompletedAuthorPage: hydrationState == NovelChapterHydrationState.ready
        ? 1
        : 0,
    lastSeenPid: null,
    lastSyncAt: hydrationState == NovelChapterHydrationState.ready
        ? DateTime(2026, 7, 13)
        : null,
    lastError: null,
  );
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
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

class _FakeNovelRepository implements NovelRepository {
  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return [
      NovelShelfCategory(
        categoryId: 'default',
        name: 'Default',
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
      sourceFid: '49',
      title: 'Test Novel',
      author: 'Author A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 1,
      categoryId: 'default',
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return const [
      NovelEpisodeItem(
        episodeId: 'novel:1:e1',
        novelId: 'novel:1',
        sourceTid: '100',
        sourcePid: '5001',
        sourcePage: 1,
        episodeTitle: 'Chapter 1',
        orderIndex: 0,
        datelineText: '2026-01-01',
      ),
    ];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async =>
      NovelReaderPreferences.defaults();

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async => null;

  @override
  Future<List<NovelItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const [];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 1,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

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

  @override
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

class _FakeLibraryStateRepository implements LibraryStateRepository {
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
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

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
    return null;
  }

  @override
  Future<List<LibraryTag>> getTags() async => const [];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const [];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
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
  }) async {}
}
