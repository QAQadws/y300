import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_cases_impl.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/services/favorite_link_service.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/thread/data/repositories/thread_favorite_repository.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  group('DefaultUnfavoriteWorkUseCase', () {
    test('all tids succeed then marks removed purges and notifies', () async {
      final repository = _FakeThreadFavoriteRepository(
        results: <String, ApiResult<ThreadUnfavoriteResult>>{
          '100': const ApiSuccess<ThreadUnfavoriteResult>(
            ThreadUnfavoriteResult(message: 'ok'),
          ),
          '101': const ApiSuccess<ThreadUnfavoriteResult>(
            ThreadUnfavoriteResult(message: 'already', alreadyRemoved: true),
          ),
        },
      );
      final favoriteLinkService = _FakeFavoriteLinkService(
        linksByWorkId: <String, FavoriteWorkLinks>{
          'yamibo:1': FavoriteWorkLinks(
            workId: 'yamibo:1',
            kind: ThreadContentKind.comic,
            threads: const <FavoriteThreadRef>[
              FavoriteThreadRef(tid: '100'),
              FavoriteThreadRef(tid: '101'),
            ],
          ),
        },
        activeByWorkId: <String, bool>{'yamibo:1': false},
      );
      final localRepository = _FakeLocalFavoriteRepository();
      final workPurgeService = _FakeWorkPurgeService();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final useCase = DefaultUnfavoriteWorkUseCase(
        threadFavoriteRepository: repository,
        favoriteLinkService: favoriteLinkService,
        localFavoriteRepository: localRepository,
        workPurgeService: workPurgeService,
        shelfRefreshBus: bus,
      );

      final result = await useCase.call(
        workId: 'yamibo:1',
        kind: ThreadContentKind.comic,
      );

      expect(result.requestedTids, <String>['100', '101']);
      expect(result.succeededTids, <String>['100', '101']);
      expect(result.failedTids, isEmpty);
      expect(result.purgedWorkIds, <String>['yamibo:1']);
      expect(repository.calledTids, <String>['100', '101']);
      expect(localRepository.markRemovedByTidsCalls, <Set<String>>[
        <String>{'100', '101'},
      ]);
      expect(workPurgeService.calls, <_PurgeCall>[
        const _PurgeCall('yamibo:1', ThreadContentKind.comic),
      ]);
      expect(bus.signal.value?.reason, 'work_unfavorite_completed');
      expect(
        bus.signal.value?.modules,
        const <LibraryModuleKey>{
          LibraryModuleKey.favorite,
          LibraryModuleKey.comic,
        },
      );
      expect(bus.signal.value?.payload['requestedTidCount'], 2);
      expect(bus.signal.value?.payload['triggeredPurge'], isTrue);
    });

    test('partial failure marks only successful tids and skips purge', () async {
      final repository = _FakeThreadFavoriteRepository(
        results: <String, ApiResult<ThreadUnfavoriteResult>>{
          '100': const ApiSuccess<ThreadUnfavoriteResult>(
            ThreadUnfavoriteResult(message: 'ok'),
          ),
          '101': const ApiFailure<ThreadUnfavoriteResult>(
            ApiError(type: ApiErrorType.business, message: 'boom'),
          ),
        },
      );
      final favoriteLinkService = _FakeFavoriteLinkService(
        linksByWorkId: <String, FavoriteWorkLinks>{
          'yamibo:2': FavoriteWorkLinks(
            workId: 'yamibo:2',
            kind: ThreadContentKind.comic,
            threads: const <FavoriteThreadRef>[
              FavoriteThreadRef(tid: '100'),
              FavoriteThreadRef(tid: '101'),
            ],
          ),
        },
        activeByWorkId: <String, bool>{'yamibo:2': true},
      );
      final localRepository = _FakeLocalFavoriteRepository();
      final workPurgeService = _FakeWorkPurgeService();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final useCase = DefaultUnfavoriteWorkUseCase(
        threadFavoriteRepository: repository,
        favoriteLinkService: favoriteLinkService,
        localFavoriteRepository: localRepository,
        workPurgeService: workPurgeService,
        shelfRefreshBus: bus,
      );

      final result = await useCase.call(
        workId: 'yamibo:2',
        kind: ThreadContentKind.comic,
      );

      expect(result.succeededTids, <String>['100']);
      expect(result.failedTids, <String>['101']);
      expect(result.purgedWorkIds, isEmpty);
      expect(localRepository.markRemovedByTidsCalls, <Set<String>>[
        <String>{'100'},
      ]);
      expect(workPurgeService.calls, isEmpty);
      expect(bus.signal.value?.reason, 'work_unfavorite_partially_completed');
      expect(
        bus.signal.value?.modules,
        const <LibraryModuleKey>{LibraryModuleKey.favorite},
      );
      expect(bus.signal.value?.payload['failedTidCount'], 1);
    });

    test('already removed locally does not notify without purge', () async {
      final repository = _FakeThreadFavoriteRepository(
        results: <String, ApiResult<ThreadUnfavoriteResult>>{
          '100': const ApiSuccess<ThreadUnfavoriteResult>(
            ThreadUnfavoriteResult(message: 'already', alreadyRemoved: true),
          ),
        },
      );
      final favoriteLinkService = _FakeFavoriteLinkService(
        linksByWorkId: <String, FavoriteWorkLinks>{
          'yamibo:3': FavoriteWorkLinks(
            workId: 'yamibo:3',
            kind: ThreadContentKind.comic,
            threads: const <FavoriteThreadRef>[FavoriteThreadRef(tid: '100')],
          ),
        },
        activeByWorkId: <String, bool>{'yamibo:3': true},
      );
      final localRepository = _FakeLocalFavoriteRepository(changedCount: 0);
      final workPurgeService = _FakeWorkPurgeService();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final useCase = DefaultUnfavoriteWorkUseCase(
        threadFavoriteRepository: repository,
        favoriteLinkService: favoriteLinkService,
        localFavoriteRepository: localRepository,
        workPurgeService: workPurgeService,
        shelfRefreshBus: bus,
      );

      final result = await useCase.call(
        workId: 'yamibo:3',
        kind: ThreadContentKind.comic,
      );

      expect(result.succeededTids, <String>['100']);
      expect(workPurgeService.calls, isEmpty);
      expect(localRepository.markRemovedByTidsCalls, <Set<String>>[
        <String>{'100'},
      ]);
      expect(bus.signal.value, isNull);
    });

    test('empty links returns empty result without side effects', () async {
      final repository = _FakeThreadFavoriteRepository(results: const {});
      final favoriteLinkService = _FakeFavoriteLinkService(
        linksByWorkId: const <String, FavoriteWorkLinks>{},
        activeByWorkId: const <String, bool>{},
      );
      final localRepository = _FakeLocalFavoriteRepository();
      final workPurgeService = _FakeWorkPurgeService();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final useCase = DefaultUnfavoriteWorkUseCase(
        threadFavoriteRepository: repository,
        favoriteLinkService: favoriteLinkService,
        localFavoriteRepository: localRepository,
        workPurgeService: workPurgeService,
        shelfRefreshBus: bus,
      );

      final result = await useCase.call(
        workId: 'yamibo:none',
        kind: ThreadContentKind.comic,
      );

      expect(result.requestedTids, isEmpty);
      expect(repository.calledTids, isEmpty);
      expect(localRepository.markRemovedByTidsCalls, isEmpty);
      expect(workPurgeService.calls, isEmpty);
      expect(bus.signal.value, isNull);
    });

    test('callMany merges results in iteration order', () async {
      final repository = _FakeThreadFavoriteRepository(
        results: <String, ApiResult<ThreadUnfavoriteResult>>{
          '100': const ApiSuccess<ThreadUnfavoriteResult>(
            ThreadUnfavoriteResult(message: 'ok'),
          ),
          '200': const ApiFailure<ThreadUnfavoriteResult>(
            ApiError(type: ApiErrorType.business, message: 'bad'),
          ),
        },
      );
      final favoriteLinkService = _FakeFavoriteLinkService(
        linksByWorkId: <String, FavoriteWorkLinks>{
          'yamibo:1': FavoriteWorkLinks(
            workId: 'yamibo:1',
            kind: ThreadContentKind.comic,
            threads: const <FavoriteThreadRef>[FavoriteThreadRef(tid: '100')],
          ),
          'novel:1': FavoriteWorkLinks(
            workId: 'novel:1',
            kind: ThreadContentKind.novel,
            threads: const <FavoriteThreadRef>[FavoriteThreadRef(tid: '200')],
          ),
        },
        activeByWorkId: <String, bool>{
          'yamibo:1': true,
          'novel:1': true,
        },
      );
      final useCase = DefaultUnfavoriteWorkUseCase(
        threadFavoriteRepository: repository,
        favoriteLinkService: favoriteLinkService,
        localFavoriteRepository: _FakeLocalFavoriteRepository(),
        workPurgeService: _FakeWorkPurgeService(),
        shelfRefreshBus: LibraryShelfRefreshBus(),
      );

      final result = await useCase.callMany(
        workKinds: <String, ThreadContentKind>{
          'yamibo:1': ThreadContentKind.comic,
          'novel:1': ThreadContentKind.novel,
        },
      );

      expect(result.requestedTids, <String>['100', '200']);
      expect(result.succeededTids, <String>['100']);
      expect(result.failedTids, <String>['200']);
    });
  });
}

class _FakeThreadFavoriteRepository implements ThreadFavoriteRepository {
  _FakeThreadFavoriteRepository({
    required this.results,
  });

  final Map<String, ApiResult<ThreadUnfavoriteResult>> results;
  final List<String> calledTids = <String>[];

  @override
  Future<ApiResult<ThreadFavoriteResult>> favoriteThread({
    required ThreadFavoriteRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ApiResult<ThreadUnfavoriteResult>> unfavoriteThread({
    required ThreadUnfavoriteRequest request,
  }) async {
    calledTids.add(request.tid);
    return results[request.tid] ??
        const ApiFailure<ThreadUnfavoriteResult>(
          ApiError(type: ApiErrorType.business, message: 'missing'),
        );
  }
}

class _FakeFavoriteLinkService implements FavoriteLinkService {
  _FakeFavoriteLinkService({
    required this.linksByWorkId,
    required this.activeByWorkId,
  });

  final Map<String, FavoriteWorkLinks> linksByWorkId;
  final Map<String, bool> activeByWorkId;

  @override
  Future<bool> hasAnyActiveThread(String workId) async {
    return activeByWorkId[workId] ?? false;
  }

  @override
  Future<FavoriteWorkLinks> linksForWork(String workId) async {
    return linksByWorkId[workId] ?? FavoriteWorkLinks.empty;
  }

  @override
  Future<String?> workIdForThread(String tid) async {
    return null;
  }
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  _FakeLocalFavoriteRepository({this.changedCount});

  final List<Set<String>> markRemovedByTidsCalls = <Set<String>>[];
  final int? changedCount;

  @override
  Future<int> markRemovedByTids(Set<String> tids) async {
    markRemovedByTidsCalls.add(Set<String>.from(tids));
    return changedCount ?? tids.length;
  }

  @override
  Future<int> markRemovedByWorkId(String workId) async => 0;

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async => false;

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async => null;

  @override
  Future<int> countActiveThreads() async => 0;

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<String> createCategory({required String name}) async => 'custom';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) async {}

  @override
  Future<Set<String>> getActiveTids() async => const <String>{};

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async =>
      const <FavoriteThreadCacheRecord>[];

  @override
  Future<List<FavoriteThreadCacheRecord>> getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async =>
      null;

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => null;

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async => true;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async =>
      const <LibraryWorkItem>[];

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async =>
      const <LibraryCategory>[];

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => null;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async => const <String, List<LibraryWorkItem>>{};

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  }) async => page.items.length;

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {}
}

class _FakeWorkPurgeService implements WorkPurgeService {
  final List<_PurgeCall> calls = <_PurgeCall>[];

  @override
  Future<WorkPurgeResult> purge({
    required String workId,
    required ThreadContentKind kind,
  }) async {
    calls.add(_PurgeCall(workId, kind));
    return WorkPurgeResult(
      workId: workId,
      kind: kind,
      purgedDownload: false,
      purgedCache: false,
    );
  }
}

class _PurgeCall {
  const _PurgeCall(this.workId, this.kind);

  final String workId;
  final ThreadContentKind kind;

  @override
  bool operator ==(Object other) {
    return other is _PurgeCall &&
        other.workId == workId &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(workId, kind);
}
