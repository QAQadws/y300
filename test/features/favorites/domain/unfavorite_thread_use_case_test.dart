import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_cases_impl.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/services/favorite_link_service.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

import '../../../support/favorite_command_test_support.dart';

void main() {
  group('DefaultUnfavoriteThreadUseCase', () {
    test(
      'success without work id only marks removed and refreshes favorite',
      () async {
        final bus = LibraryShelfRefreshBus();
        addTearDown(bus.dispose);
        final localRepository = _FakeLocalFavoriteRepository();
        final useCase = DefaultUnfavoriteThreadUseCase(
          favoriteThreadCommand: _FakeThreadFavoriteRepository(
            result: _applied('100'),
          ),
          favoriteLinkService: _FakeFavoriteLinkService(
            workIdByTid: const <String, String?>{},
            linksByWorkId: const <String, FavoriteWorkLinks>{},
            activeByWorkId: const <String, bool>{},
          ),
          localFavoriteRepository: localRepository,
          workPurgeService: _FakeWorkPurgeService(),
          shelfRefreshBus: bus,
        );

        final result = await useCase.call('100');

        expect(result.succeededTids, <String>['100']);
        expect(result.purgedWorkIds, isEmpty);
        expect(localRepository.markRemovedByTidsCalls, <Set<String>>[
          <String>{'100'},
        ]);
        expect(bus.signal.value?.modules, const <LibraryModuleKey>{
          LibraryModuleKey.favorite,
        });
        expect(bus.signal.value?.payload['kind'], isNull);
      },
    );

    test(
      'last comic thread triggers purge and favorite+comic refresh',
      () async {
        final bus = LibraryShelfRefreshBus();
        addTearDown(bus.dispose);
        final workPurgeService = _FakeWorkPurgeService();
        final useCase = DefaultUnfavoriteThreadUseCase(
          favoriteThreadCommand: _FakeThreadFavoriteRepository(
            result: _applied('100'),
          ),
          favoriteLinkService: _FakeFavoriteLinkService(
            workIdByTid: const <String, String?>{'100': 'yamibo:100'},
            linksByWorkId: <String, FavoriteWorkLinks>{
              'yamibo:100': FavoriteWorkLinks(
                workId: 'yamibo:100',
                kind: ThreadContentKind.comic,
                threads: const <FavoriteThreadRef>[
                  FavoriteThreadRef(tid: '100'),
                ],
              ),
            },
            activeByWorkId: const <String, bool>{'yamibo:100': false},
          ),
          localFavoriteRepository: _FakeLocalFavoriteRepository(),
          workPurgeService: workPurgeService,
          shelfRefreshBus: bus,
        );

        final result = await useCase.call('100');

        expect(result.purgedWorkIds, <String>['yamibo:100']);
        expect(workPurgeService.calls, <_PurgeCall>[
          const _PurgeCall('yamibo:100', ThreadContentKind.comic),
        ]);
        expect(bus.signal.value?.modules, const <LibraryModuleKey>{
          LibraryModuleKey.favorite,
          LibraryModuleKey.comic,
        });
      },
    );

    test('success with remaining active thread skips purge', () async {
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final workPurgeService = _FakeWorkPurgeService();
      final useCase = DefaultUnfavoriteThreadUseCase(
        favoriteThreadCommand: _FakeThreadFavoriteRepository(
          result: _applied('100'),
        ),
        favoriteLinkService: _FakeFavoriteLinkService(
          workIdByTid: const <String, String?>{'100': 'yamibo:100'},
          linksByWorkId: <String, FavoriteWorkLinks>{
            'yamibo:100': FavoriteWorkLinks(
              workId: 'yamibo:100',
              kind: ThreadContentKind.comic,
              threads: const <FavoriteThreadRef>[FavoriteThreadRef(tid: '100')],
            ),
          },
          activeByWorkId: const <String, bool>{'yamibo:100': true},
        ),
        localFavoriteRepository: _FakeLocalFavoriteRepository(),
        workPurgeService: workPurgeService,
        shelfRefreshBus: bus,
      );

      final result = await useCase.call('100');

      expect(result.purgedWorkIds, isEmpty);
      expect(workPurgeService.calls, isEmpty);
      expect(bus.signal.value?.modules, const <LibraryModuleKey>{
        LibraryModuleKey.favorite,
      });
    });

    test(
      'forum kind never purges even when last active thread is gone',
      () async {
        final workPurgeService = _FakeWorkPurgeService();
        final useCase = DefaultUnfavoriteThreadUseCase(
          favoriteThreadCommand: _FakeThreadFavoriteRepository(
            result: _applied('100'),
          ),
          favoriteLinkService: _FakeFavoriteLinkService(
            workIdByTid: const <String, String?>{'100': 'thread:100'},
            linksByWorkId: <String, FavoriteWorkLinks>{
              'thread:100': FavoriteWorkLinks(
                workId: 'thread:100',
                kind: ThreadContentKind.forum,
                threads: const <FavoriteThreadRef>[
                  FavoriteThreadRef(tid: '100'),
                ],
              ),
            },
            activeByWorkId: const <String, bool>{'thread:100': false},
          ),
          localFavoriteRepository: _FakeLocalFavoriteRepository(),
          workPurgeService: workPurgeService,
          shelfRefreshBus: LibraryShelfRefreshBus(),
        );

        final result = await useCase.call('100');

        expect(result.purgedWorkIds, isEmpty);
        expect(workPurgeService.calls, isEmpty);
      },
    );

    test(
      'api failure keeps local state untouched and does not notify',
      () async {
        final bus = LibraryShelfRefreshBus();
        addTearDown(bus.dispose);
        final localRepository = _FakeLocalFavoriteRepository();
        final workPurgeService = _FakeWorkPurgeService();
        final useCase = DefaultUnfavoriteThreadUseCase(
          favoriteThreadCommand: _FakeThreadFavoriteRepository(
            result: _failed(),
          ),
          favoriteLinkService: _FakeFavoriteLinkService(
            workIdByTid: const <String, String?>{'100': 'yamibo:100'},
            linksByWorkId: const <String, FavoriteWorkLinks>{},
            activeByWorkId: const <String, bool>{},
          ),
          localFavoriteRepository: localRepository,
          workPurgeService: workPurgeService,
          shelfRefreshBus: bus,
        );

        final result = await useCase.call('100');

        expect(result.failedTids, <String>['100']);
        expect(localRepository.markRemovedByTidsCalls, isEmpty);
        expect(workPurgeService.calls, isEmpty);
        expect(bus.signal.value, isNull);
      },
    );

    test(
      'already removed locally does not notify when no purge is needed',
      () async {
        final bus = LibraryShelfRefreshBus();
        addTearDown(bus.dispose);
        final localRepository = _FakeLocalFavoriteRepository(changedCount: 0);
        final workPurgeService = _FakeWorkPurgeService();
        final useCase = DefaultUnfavoriteThreadUseCase(
          favoriteThreadCommand: _FakeThreadFavoriteRepository(
            result: _applied('100', alreadyApplied: true),
          ),
          favoriteLinkService: _FakeFavoriteLinkService(
            workIdByTid: const <String, String?>{'100': 'yamibo:100'},
            linksByWorkId: <String, FavoriteWorkLinks>{
              'yamibo:100': FavoriteWorkLinks(
                workId: 'yamibo:100',
                kind: ThreadContentKind.comic,
                threads: const <FavoriteThreadRef>[
                  FavoriteThreadRef(tid: '100'),
                ],
              ),
            },
            activeByWorkId: const <String, bool>{'yamibo:100': true},
          ),
          localFavoriteRepository: localRepository,
          workPurgeService: workPurgeService,
          shelfRefreshBus: bus,
        );

        final result = await useCase.call('100');

        expect(result.succeededTids, <String>['100']);
        expect(localRepository.markRemovedByTidsCalls, <Set<String>>[
          <String>{'100'},
        ]);
        expect(workPurgeService.calls, isEmpty);
        expect(bus.signal.value, isNull);
      },
    );

    test('callMany merges results in iteration order', () async {
      final useCase = DefaultUnfavoriteThreadUseCase(
        favoriteThreadCommand: _SequencedThreadFavoriteRepository(
          results: <String, DataCommandResult<ThreadFavoriteReceipt>>{
            '100': _applied('100'),
            '200': _failed(),
          },
        ),
        favoriteLinkService: _FakeFavoriteLinkService(
          workIdByTid: const <String, String?>{},
          linksByWorkId: const <String, FavoriteWorkLinks>{},
          activeByWorkId: const <String, bool>{},
        ),
        localFavoriteRepository: _FakeLocalFavoriteRepository(),
        workPurgeService: _FakeWorkPurgeService(),
        shelfRefreshBus: LibraryShelfRefreshBus(),
      );

      final result = await useCase.callMany(<String>{'100', '200'});

      expect(result.requestedTids, <String>['100', '200']);
      expect(result.succeededTids, <String>['100']);
      expect(result.failedTids, <String>['200']);
    });
  });
}

class _FakeThreadFavoriteRepository implements FavoriteThreadCommand {
  _FakeThreadFavoriteRepository({required this.result});

  final DataCommandResult<ThreadFavoriteReceipt> result;

  @override
  FavoriteMutationCapabilities get capabilities =>
      allFavoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ThreadFavoriteReceipt>> execute(
    SetThreadFavoriteRequest request,
  ) async => result;
}

class _SequencedThreadFavoriteRepository implements FavoriteThreadCommand {
  _SequencedThreadFavoriteRepository({required this.results});

  final Map<String, DataCommandResult<ThreadFavoriteReceipt>> results;

  @override
  FavoriteMutationCapabilities get capabilities =>
      allFavoriteMutationCapabilities;

  @override
  Future<DataCommandResult<ThreadFavoriteReceipt>> execute(
    SetThreadFavoriteRequest request,
  ) async {
    return results[request.tid] ??
        DataCommandRejected<ThreadFavoriteReceipt>(
          fixtureFavoriteFailure(code: 'fixture_missing_result'),
        );
  }
}

DataCommandApplied<ThreadFavoriteReceipt> _applied(
  String tid, {
  bool alreadyApplied = false,
}) => appliedThreadFavorite(
  tid: tid,
  targetState: FavoriteTargetState.unfavorited,
  disposition: alreadyApplied
      ? FavoriteMutationDisposition.alreadyApplied
      : FavoriteMutationDisposition.changed,
);

DataCommandOutcomeUnknown<ThreadFavoriteReceipt> _failed() =>
    DataCommandOutcomeUnknown<ThreadFavoriteReceipt>(fixtureFavoriteFailure());

class _FakeFavoriteLinkService implements FavoriteLinkService {
  _FakeFavoriteLinkService({
    required this.workIdByTid,
    required this.linksByWorkId,
    required this.activeByWorkId,
  });

  final Map<String, String?> workIdByTid;
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
    return workIdByTid[tid];
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
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async =>
      null;

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
  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(
    String workId,
  ) async => null;

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
  Future<int> upsertRemoteThreads(
    List<FavoriteThreadCacheUpsert> items,
  ) async => items.length;

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
    return other is _PurgeCall && other.workId == workId && other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(workId, kind);
}
