import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/data/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  testWidgets('FavoriteShelfPage builds unified shelf in list mode', (tester) async {
    final bootstrapper = _RecordingFavoriteShelfBootstrapper();
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
        ],
        child: const MaterialApp(home: FavoriteShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.byKey(const Key('unified-shelf-list-view')), findsOneWidget);
    expect(find.text('收藏帖'), findsOneWidget);
    expect(bootstrapper.startCallCount, 1);
  });

  testWidgets('FavoriteShelfPage shows first-sync progress while cache is building', (tester) async {
    final sync = _FakeFavoriteSyncService(autoComplete: false);
    final bootstrapper = _RecordingFavoriteShelfBootstrapper(
      onStart: () async {
        await sync.sync();
      },
    );
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository(hasSnapshot: false)),
          favoriteSyncServiceProvider.overrideWith((ref) => sync),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
        ],
        child: const MaterialApp(home: FavoriteShelfPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsOneWidget);
    expect(find.text('正在解析: 收藏帖'), findsOneWidget);
    expect(bootstrapper.startCallCount, 1);
    sync.completePendingSync();
    await tester.pumpAndSettle();
  });

  testWidgets('FavoriteShelfPage hides first-sync banner when notification permission is granted', (tester) async {
    final sync = _FakeFavoriteSyncService(autoComplete: false);
    final bootstrapper = _RecordingFavoriteShelfBootstrapper(
      onStart: () async {
        await sync.sync();
      },
    );
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final notificationService = _FakeLibraryTaskNotificationService(
      initialPermission: LibraryTaskNotificationPermissionState.granted,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository(hasSnapshot: false)),
          favoriteSyncServiceProvider.overrideWith((ref) => sync),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          libraryTaskNotificationServiceProvider.overrideWithValue(notificationService),
        ],
        child: const MaterialApp(home: FavoriteShelfPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsNothing);
    expect(bootstrapper.startCallCount, 1);
    sync.completePendingSync();
    await tester.pumpAndSettle();
  });
}

class _RecordingFavoriteShelfBootstrapper implements FavoriteShelfBootstrapper {
  _RecordingFavoriteShelfBootstrapper({
    Future<void> Function()? onStart,
  }) : _onStart = onStart;

  final Future<void> Function()? _onStart;
  int startCallCount = 0;

  @override
  Future<void> startIfNeeded() async {
    startCallCount++;
    await _onStart?.call();
  }
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  _FakeFavoriteSyncService({this.autoComplete = true});

  final bool autoComplete;
  final _progress = ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);
  Completer<FavoriteSyncResult>? _pendingCompleter;

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {}

  @override
  Future<FavoriteSyncResult> sync() async {
    _progress.value = const FavoriteSyncProgress(
      phase: FavoriteSyncProgressPhase.loadingDetails,
      message: '正在解析: 收藏帖',
      current: 1,
      total: 10,
    );
    if (!autoComplete) {
      _pendingCompleter = Completer<FavoriteSyncResult>();
      return _pendingCompleter!.future;
    }
    _progress.value = FavoriteSyncProgress.idle;
    return const FavoriteSyncResult(
      mode: FavoriteSyncMode.incremental,
      remoteCount: 1,
      fetchedPages: 1,
      upsertedCount: 0,
      removedRecords: <FavoriteThreadCacheRecord>[],
      detailLoadedCount: 0,
      failedDetailTids: <String>[],
    );
  }

  @override
  Future<FavoriteSyncResult> syncRecentlyAddedThread({
    required String tid,
  }) {
    return sync();
  }

  void completePendingSync() {
    final completer = _pendingCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    _progress.value = FavoriteSyncProgress.idle;
    completer.complete(
      const FavoriteSyncResult(
        mode: FavoriteSyncMode.incremental,
        remoteCount: 1,
        fetchedPages: 1,
        upsertedCount: 0,
        removedRecords: <FavoriteThreadCacheRecord>[],
        detailLoadedCount: 0,
        failedDetailTids: <String>[],
      ),
    );
  }
}

class _FakeLibraryTaskNotificationService
    implements LibraryTaskNotificationService {
  _FakeLibraryTaskNotificationService({
    required LibraryTaskNotificationPermissionState? initialPermission,
  }) : _permissionState =
           ValueNotifier<LibraryTaskNotificationPermissionState?>(
             initialPermission,
           );

  final ValueNotifier<LibraryTaskNotificationPermissionState?> _permissionState;

  @override
  ValueListenable<LibraryTaskNotificationPermissionState?> get permissionState =>
      _permissionState;

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {}

  @override
  Future<LibraryTaskNotificationPermissionState> ensurePermission() async {
    return _permissionState.value ??
        LibraryTaskNotificationPermissionState.denied;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showOrUpdate(LibraryTaskNotification notification) async {}
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  _FakeLocalFavoriteRepository({this.hasSnapshot = true});

  final bool hasSnapshot;
  final _category = LibraryCategory(
    categoryId: favoriteDefaultCategoryId,
    name: '默认',
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  final _item = LibraryWorkItem(
    workId: FavoriteShelfWorkId.fromTid('100'),
    categoryId: favoriteDefaultCategoryId,
    title: '收藏帖',
    secondaryName: '作者A',
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );

  @override
  Future<int> countActiveThreads() async => 1;

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<String> createCategory({required String name}) async => 'custom';
  @override
  Future<void> deleteCategory({required String categoryId}) async {}
  @override
  Future<void> finishSync({required FavoriteSyncMode mode, required int remoteCount, String? status, String? message}) async {}
  @override
  Future<Set<String>> getActiveTids() async => const <String>{'100'};
  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async => const <FavoriteThreadCacheRecord>[];
  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async => true;
  @override
  Future<void> markComicAutoRefreshBackfillCompleted({required int checkedCount, String? message}) async {}
  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async => null;
  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(String workId) async =>
      const <FavoriteThreadCacheRecord>[];
  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async => false;
  @override
  Future<int> markRemovedByWorkId(String workId) async => 0;
  @override
  Future<int> markRemovedByTids(Set<String> tids) async => 0;
  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];
  @override
  Future<List<FavoriteThreadCacheRecord>> getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];
  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async {
    return const FavoriteRouteTarget(
      tid: '100',
      title: '收藏帖',
      contentKind: ThreadContentKind.forum,
      workId: 'thread:100',
    );
  }
  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    if (!hasSnapshot) {
      return null;
    }
    return FavoriteSyncSnapshot(
      syncKey: favoriteSyncKey,
      remoteCount: 1,
      localActiveCount: 1,
      lastSyncedAt: DateTime(2026, 1, 1),
    );
  }
  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async => <LibraryWorkItem>[_item];
  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async => <LibraryCategory>[_category];
  @override
  Future<void> markSyncFailure(String message) async {}
  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(Set<String> activeRemoteTids) async => const <FavoriteThreadCacheRecord>[];
  @override
  Future<void> moveThreadToCategory({required String tid, required String toCategoryId}) async {}
  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => _item.workId;
  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return <String, List<LibraryWorkItem>>{
      for (final category in categories) category.categoryId: <LibraryWorkItem>[_item],
    };
  }
  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}
  @override
  Future<void> updateThreadDetailMeta({required String tid, required String fid, required String typeid, required String? tagName, required ThreadContentKind contentKind, required String? workId}) async {}
  @override
  Future<int> upsertRemotePage({required FavoriteThreadsPage page, required int pageStartOrder}) async => page.items.length;
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
  Future<void> upsertEpisodeState({required LibraryModuleKey moduleKey, required String episodeId, required String workId, bool? isRead, bool? isDownloaded, bool? isBookmarked, DateTime? readAt, DateTime? downloadedAt}) async {}
  @override
  Future<void> upsertWorkState({required LibraryModuleKey moduleKey, required String workId, String? lastReadEpisodeId, DateTime? lastReadAt, DateTime? checkUpdatedAt, DateTime? fetchedUpdatedAt, String? introText}) async {}
}
