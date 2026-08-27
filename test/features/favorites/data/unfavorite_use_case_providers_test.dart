import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/providers/work_purge_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

import '../../../support/favorite_command_test_support.dart';

void main() {
  test('unfavorite use case providers can construct both use cases', () {
    final container = ProviderContainer(
      overrides: [
        localFavoriteRepositoryProvider.overrideWithValue(
          _FakeLocalFavoriteRepository(),
        ),
        favoriteThreadCommandProvider.overrideWithValue(
          FakeFavoriteThreadCommand(),
        ),
        workPurgeServiceProvider.overrideWithValue(_FakeWorkPurgeService()),
        libraryShelfRefreshBusProvider.overrideWith((ref) {
          final bus = LibraryShelfRefreshBus();
          ref.onDispose(bus.dispose);
          return bus;
        }),
      ],
    );
    addTearDown(container.dispose);

    final workUseCase = container.read(unfavoriteWorkUseCaseProvider);
    final threadUseCase = container.read(unfavoriteThreadUseCaseProvider);

    expect(workUseCase, isA<UnfavoriteWorkUseCase>());
    expect(threadUseCase, isA<UnfavoriteThreadUseCase>());
  });
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => null;

  @override
  Future<int> countActiveThreads() async => 0;

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<Set<String>> getActiveTids() async => const <String>{};

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async =>
      const <FavoriteThreadCacheRecord>[];

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
  Future<int> upsertRemoteThreads(
    List<FavoriteThreadCacheUpsert> items,
  ) async => items.length;

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

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
  Future<void> markThreadDetailInvalid({required String tid}) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async =>
      null;

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async => false;

  @override
  Future<int> markRemovedByWorkId(String workId) async => 0;

  @override
  Future<int> markRemovedByTids(Set<String> tids) async => tids.length;

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(
    String workId,
  ) async => null;

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async =>
      const <LibraryCategory>[];

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async =>
      const <LibraryWorkItem>[];

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async => const <String, List<LibraryWorkItem>>{};

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

class _FakeWorkPurgeService implements WorkPurgeService {
  @override
  Future<WorkPurgeResult> purge({
    required String workId,
    required ThreadContentKind kind,
  }) async {
    return WorkPurgeResult(
      workId: workId,
      kind: kind,
      purgedDownload: false,
      purgedCache: false,
    );
  }
}
