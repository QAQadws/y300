import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('FavoriteShelfBootstrapper runs full sync when snapshot is missing', () async {
    final repository = _FakeLocalFavoriteRepository(snapshot: null);
    final syncService = _FakeFavoriteSyncService();
    final bootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: repository,
      syncService: syncService,
    );

    await bootstrapper.startIfNeeded();

    expect(syncService.syncCount, 1);
    expect(syncService.maintenanceCount, 0);
  });

  test('FavoriteShelfBootstrapper runs sync when snapshot has missing details', () async {
    final repository = _FakeLocalFavoriteRepository(
      snapshot: _snapshot(),
      missingDetailCount: 2,
    );
    final syncService = _FakeFavoriteSyncService();
    final bootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: repository,
      syncService: syncService,
    );

    await bootstrapper.startIfNeeded();

    expect(syncService.syncCount, 1);
    expect(syncService.maintenanceCount, 0);
  });

  test('FavoriteShelfBootstrapper runs maintenance when snapshot is complete', () async {
    final repository = _FakeLocalFavoriteRepository(
      snapshot: _snapshot(),
      missingDetailCount: 0,
    );
    final syncService = _FakeFavoriteSyncService();
    final bootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: repository,
      syncService: syncService,
    );

    await bootstrapper.startIfNeeded();

    expect(syncService.syncCount, 0);
    expect(syncService.maintenanceCount, 1);
  });

  test('FavoriteShelfBootstrapper only starts once while first run is in flight', () async {
    final repository = _FakeLocalFavoriteRepository(snapshot: null);
    final syncService = _FakeFavoriteSyncService()..pauseNextSync();
    final bootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: repository,
      syncService: syncService,
    );

    final first = bootstrapper.startIfNeeded();
    final second = bootstrapper.startIfNeeded();

    await syncService.syncStarted;

    expect(syncService.syncCount, 1);
    expect(identical(first, second), isTrue);

    syncService.completePausedSync();
    await Future.wait(<Future<void>>[first, second]);
  });

  test('FavoriteShelfBootstrapper swallows repository and sync failures', () async {
    final failingRepository = _FakeLocalFavoriteRepository(
      throwOnGetSnapshot: true,
    );
    final failingSync = _FakeFavoriteSyncService(throwOnSync: true);

    final firstBootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: failingRepository,
      syncService: _FakeFavoriteSyncService(),
    );
    final secondBootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: _FakeLocalFavoriteRepository(snapshot: null),
      syncService: failingSync,
    );

    await firstBootstrapper.startIfNeeded();
    await secondBootstrapper.startIfNeeded();

    expect(failingSync.syncCount, 1);
  });

  test('FavoriteShelfBootstrapper retries after failed run', () async {
    final repository = _FakeLocalFavoriteRepository(snapshot: null);
    final syncService = _FakeFavoriteSyncService(throwOnSync: true);
    final bootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: repository,
      syncService: syncService,
    );

    await bootstrapper.startIfNeeded();
    await bootstrapper.startIfNeeded();

    expect(syncService.syncCount, 2);
  });

  test('FavoriteShelfBootstrapper does not rerun after stable baseline exists', () async {
    final repository = _FakeLocalFavoriteRepository(
      snapshot: _snapshot(),
      missingDetailCount: 0,
    );
    final syncService = _FakeFavoriteSyncService();
    final bootstrapper = DefaultFavoriteShelfBootstrapper(
      repository: repository,
      syncService: syncService,
    );

    await bootstrapper.startIfNeeded();
    await bootstrapper.startIfNeeded();

    expect(syncService.syncCount, 0);
    expect(syncService.maintenanceCount, 1);
  });
}

FavoriteSyncSnapshot _snapshot() {
  return FavoriteSyncSnapshot(
    syncKey: favoriteSyncKey,
    remoteCount: 1,
    localActiveCount: 1,
    lastSyncedAt: DateTime(2026, 1, 1),
  );
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  _FakeFavoriteSyncService({this.throwOnSync = false});

  final bool throwOnSync;
  final ValueNotifier<FavoriteSyncProgress> _progress =
      ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);
  Completer<void>? _pausedSync;
  Completer<void>? _syncStarted;
  int syncCount = 0;
  int maintenanceCount = 0;

  @override
  ValueNotifier<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {
    maintenanceCount++;
  }

  @override
  Future<FavoriteSyncResult> sync() async {
    syncCount++;
    final started = _syncStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    if (throwOnSync) {
      throw StateError('sync failed');
    }
    await (_pausedSync?.future ?? Future<void>.value());
    return const FavoriteSyncResult(
      mode: FavoriteSyncMode.fullDiff,
      remoteCount: 1,
      fetchedPages: 1,
      upsertedCount: 1,
      removedRecords: <FavoriteThreadCacheRecord>[],
      detailLoadedCount: 0,
      failedDetailTids: <String>[],
    );
  }

  @override
  Future<FavoriteSyncResult> syncRecentlyAddedThread({required String tid}) {
    return sync();
  }

  Future<void> get syncStarted => _syncStarted?.future ?? Future<void>.value();

  void pauseNextSync() {
    _pausedSync = Completer<void>();
    _syncStarted = Completer<void>();
  }

  void completePausedSync() {
    final paused = _pausedSync;
    if (paused != null && !paused.isCompleted) {
      paused.complete();
    }
  }
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  _FakeLocalFavoriteRepository({
    this.snapshot,
    this.missingDetailCount = 0,
    this.throwOnGetSnapshot = false,
  });

  final FavoriteSyncSnapshot? snapshot;
  final int missingDetailCount;
  final bool throwOnGetSnapshot;

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    if (throwOnGetSnapshot) {
      throw StateError('snapshot failed');
    }
    return snapshot;
  }

  @override
  Future<int> countMissingDetailRecords() async => missingDetailCount;

  @override
  Future<int> countActiveThreads() async => 0;

  @override
  Future<Set<String>> getActiveTids() async => const <String>{};

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async => true;

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {}

  @override
  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) async {}

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  }) async {
    return page.items.length;
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async {
    return null;
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async => false;

  @override
  Future<int> markRemovedByWorkId(String workId) async => 0;

  @override
  Future<int> markRemovedByTids(Set<String> tids) async => 0;

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async {
    return null;
  }

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async {
    return const <LibraryCategory>[];
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    return const <LibraryWorkItem>[];
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return const <String, List<LibraryWorkItem>>{};
  }

  @override
  Future<String> createCategory({required String name}) async => 'custom';

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => null;
}
