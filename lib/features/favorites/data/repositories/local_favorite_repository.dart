import 'package:sqflite/sqflite.dart' show Database;
import 'package:y300/features/favorites/data/repositories/local/favorite_sync_store.dart';
import 'package:y300/features/favorites/data/repositories/local/favorite_category_store.dart';
import 'package:y300/features/favorites/data/repositories/local/favorite_shelf_read_model.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

abstract class LocalFavoriteRepository {
  Future<FavoriteSyncSnapshot?> getSyncSnapshot();

  Future<int> countActiveThreads();

  Future<int> countMissingDetailRecords();

  Future<Set<String>> getActiveTids();

  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot();

  Future<bool> hasCompletedComicAutoRefreshBackfill();

  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  });

  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  });

  Future<void> markSyncFailure(String message);

  Future<int> upsertRemoteThreads(List<FavoriteThreadCacheUpsert> items);

  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  });

  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  });

  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  });

  Future<void> markThreadDetailInvalid({required String tid});

  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  );

  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid);

  /// 一个作品（workId）当前关联的全部活跃收藏帖。
  ///
  /// 合并机制会把多个收藏帖重指向同一 workId，因此可能返回多条。
  /// 用于「取消整部作品」时逐个 tid 删除。
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  );

  /// 作品是否还有任意活跃收藏来源。取消收藏后据此决定是否清除作品。
  Future<bool> hasActiveThreadForWorkId(String workId);

  /// 按作品统一标记本地收藏行为已移除。
  Future<int> markRemovedByWorkId(String workId) {
    throw UnimplementedError('markRemovedByWorkId($workId)');
  }

  /// 只按指定 tid 标记本地收藏行为已移除。
  ///
  /// 用于取消收藏阶段 3 的“部分 tid 成功、部分失败”场景，避免按 workId
  /// 批量标记时把失败 tid 一起误删。
  Future<int> markRemovedByTids(Set<String> tids) {
    throw UnimplementedError('markRemovedByTids($tids)');
  }

  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId);

  Future<List<LibraryCategory>> loadVisibleCategories();

  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId);

  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });

  Future<String> createCategory({required String name});

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  });

  Future<void> deleteCategory({required String categoryId});

  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  });

  Future<String?> pickRandomWorkId({required String categoryId});
}

abstract class FavoriteShelfSnapshotRepository {
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });
}

/// Keeps the public repository stable while stores own their SQLite operations.
class SqfliteLocalFavoriteRepository
    implements LocalFavoriteRepository, FavoriteShelfSnapshotRepository {
  SqfliteLocalFavoriteRepository(Future<Database> database)
    : _syncStore = FavoriteSyncStore(database),
      _categoryStore = FavoriteCategoryStore(database) {
    _shelfReadModel = FavoriteShelfReadModel(
      database,
      categoryStore: _categoryStore,
    );
  }

  final FavoriteSyncStore _syncStore;
  final FavoriteCategoryStore _categoryStore;
  late final FavoriteShelfReadModel _shelfReadModel;

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() =>
      _syncStore.getSyncSnapshot();

  @override
  Future<int> countActiveThreads() => _syncStore.countActiveThreads();

  @override
  Future<int> countMissingDetailRecords() =>
      _syncStore.countMissingDetailRecords();

  @override
  Future<Set<String>> getActiveTids() => _syncStore.getActiveTids();

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() =>
      _syncStore.getActiveThreadsForSnapshot();

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() =>
      _syncStore.hasCompletedComicAutoRefreshBackfill();

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) => _syncStore.markComicAutoRefreshBackfillCompleted(
    checkedCount: checkedCount,
    message: message,
  );

  @override
  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) => _syncStore.finishSync(
    mode: mode,
    remoteCount: remoteCount,
    status: status,
    message: message,
  );

  @override
  Future<void> markSyncFailure(String message) =>
      _syncStore.markSyncFailure(message);

  @override
  Future<int> upsertRemoteThreads(List<FavoriteThreadCacheUpsert> items) =>
      _syncStore.upsertRemoteThreads(items);

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) => _syncStore.getMissingDetailRecords(
    limit: limit,
    excludedTids: excludedTids,
  );

  @override
  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) => _syncStore.getComicAutoRefreshBackfillCandidates(
    limit: limit,
    excludedTids: excludedTids,
  );

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) => _syncStore.updateThreadDetailMeta(
    tid: tid,
    fid: fid,
    typeid: typeid,
    tagName: tagName,
    contentKind: contentKind,
    workId: workId,
  );

  @override
  Future<void> markThreadDetailInvalid({required String tid}) =>
      _syncStore.markThreadDetailInvalid(tid: tid);

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) => _syncStore.markRemovedTids(activeRemoteTids);

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) =>
      _syncStore.getActiveThreadByTid(tid);

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) => _syncStore.getActiveThreadsByWorkId(workId);

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) =>
      _syncStore.hasActiveThreadForWorkId(workId);

  @override
  Future<int> markRemovedByWorkId(String workId) =>
      _syncStore.markRemovedByWorkId(workId);

  @override
  Future<int> markRemovedByTids(Set<String> tids) =>
      _syncStore.markRemovedByTids(tids);

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(
    String workId,
  ) async {
    final tid = FavoriteShelfWorkId.parseTid(workId);
    if (tid == null) {
      return null;
    }
    final record = await getActiveThreadByTid(tid);
    if (record == null) {
      return null;
    }
    return FavoriteRouteTarget(
      tid: record.tid,
      title: record.title,
      contentKind: record.contentKind,
      workId: record.workId,
    );
  }

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() =>
      _categoryStore.loadVisibleCategories();

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) =>
      _shelfReadModel.loadCategoryItems(categoryId);

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) => _shelfReadModel.queryItems(
    categories: categories,
    filters: filters,
    sortOption: sortOption,
    keyword: keyword,
  );

  @override
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) => _shelfReadModel.queryShelfSnapshot(
    filters: filters,
    sortOption: sortOption,
    keyword: keyword,
  );

  @override
  Future<String> createCategory({required String name}) =>
      _categoryStore.createCategory(name: name);

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) => _categoryStore.renameCategory(categoryId: categoryId, newName: newName);

  @override
  Future<void> deleteCategory({required String categoryId}) =>
      _categoryStore.deleteCategory(categoryId: categoryId);

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) =>
      _categoryStore.moveThreadToCategory(tid: tid, toCategoryId: toCategoryId);

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) =>
      _shelfReadModel.pickRandomWorkId(categoryId: categoryId);
}
