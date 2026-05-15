import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  testWidgets('FavoriteShelfPage builds unified shelf in list mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
        ],
        child: const MaterialApp(home: FavoriteShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.byKey(const Key('unified-shelf-list-view')), findsOneWidget);
    expect(find.text('收藏帖'), findsOneWidget);
  });

  testWidgets('FavoriteShelfPage shows first-sync progress while cache is building', (tester) async {
    final sync = _FakeFavoriteSyncService(autoComplete: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository(hasSnapshot: false)),
          favoriteSyncServiceProvider.overrideWith((ref) => sync),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
        ],
        child: const MaterialApp(home: FavoriteShelfPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsOneWidget);
    expect(find.text('正在解析收藏详情'), findsOneWidget);
    sync.completePendingSync();
    await tester.pumpAndSettle();
  });
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  _FakeFavoriteSyncService({this.autoComplete = true});

  final bool autoComplete;
  final _progress = ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);
  Completer<FavoriteSyncResult>? _pendingCompleter;

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<FavoriteSyncResult> sync() async {
    _progress.value = const FavoriteSyncProgress(
      phase: FavoriteSyncProgressPhase.loadingDetails,
      message: '正在解析收藏详情',
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
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async => null;
  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
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
