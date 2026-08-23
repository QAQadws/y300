import 'dart:io' as io;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/comic/data/services/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/services/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/favorites/data/services/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/services/novel_favorite_ingest_service.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

const _longRunningTagName = '長篇連載';

void main() {
  test(
    'first sync fetches all pages and ingests comic and novel details',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 3,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '漫画'),
            _favoriteThread(tid: '200', title: '小说'),
          ],
        ),
        2: _page(
          page: 2,
          totalCount: 3,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '300', title: '普通帖'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository();
      final comicIngest = _FakeComicIngestService();
      final novelIngest = _FakeNovelIngestService();
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(),
        comicIngestService: comicIngest,
        novelIngestService: novelIngest,
        detailBatchLimit: 10,
      );

      final result = await service.sync();

      expect(remote.requestedPages, <int>[1, 2]);
      expect(result.mode, FavoriteSyncMode.fullDiff);
      expect(result.detailLoadedCount, 3);
      expect(comicIngest.upsertedTids, <String>['100']);
      expect(novelIngest.upsertedTids, <String>['200']);
      expect(local.records['300']?.contentKind, ThreadContentKind.forum);
    },
  );

  test(
    'first sync classifies empty postlist as a completed invalid detail',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '404', title: '失效收藏'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository();
      final comicIngest = _FakeComicIngestService();
      final novelIngest = _FakeNovelIngestService();
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) async =>
              ApiSuccess(_invalidDetailForTid(tid)),
        ),
        comicIngestService: comicIngest,
        novelIngestService: novelIngest,
        detailBatchLimit: 10,
      );

      final result = await service.sync();

      expect(result.mode, FavoriteSyncMode.fullDiff);
      expect(result.detailLoadedCount, 1);
      expect(result.failedDetailTids, isEmpty);
      expect(local.records['404']?.detailState, FavoriteDetailState.invalid);
      expect(local.records['404']?.contentKind, ThreadContentKind.unknown);
      expect(local.records['404']?.workId, isNull);
      expect(comicIngest.upsertedTids, isEmpty);
      expect(novelIngest.upsertedTids, isEmpty);
    },
  );

  test(
    'incremental sync persists invalid detail without retrying it',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 2,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '404', title: '新增失效收藏'),
            _favoriteThread(tid: '999', title: '旧收藏'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository(
        snapshot: FavoriteSyncSnapshot(
          syncKey: favoriteSyncKey,
          remoteCount: 1,
          localActiveCount: 1,
          lastSyncedAt: DateTime(2026, 1, 1),
        ),
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '999',
            title: '旧收藏',
            contentKind: ThreadContentKind.forum,
            workId: 'thread:999',
            detailLoadedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      var detailLoadCount = 0;
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) async {
            detailLoadCount++;
            return ApiSuccess(_invalidDetailForTid(tid));
          },
        ),
        detailBatchLimit: 10,
      );

      final first = await service.sync();
      final second = await service.sync();

      expect(first.mode, FavoriteSyncMode.incremental);
      expect(first.failedDetailTids, isEmpty);
      expect(second.failedDetailTids, isEmpty);
      expect(local.records['404']?.detailState, FavoriteDetailState.invalid);
      expect(detailLoadCount, 1);
    },
  );

  test('recently added sync accepts an empty postlist as invalid', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 2,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '404', title: '刚收藏的失效帖'),
          _favoriteThread(tid: '999', title: '旧收藏'),
        ],
      ),
    });
    final local = _MemoryLocalFavoriteRepository(
      snapshot: FavoriteSyncSnapshot(
        syncKey: favoriteSyncKey,
        remoteCount: 1,
        localActiveCount: 1,
        lastSyncedAt: DateTime(2026, 1, 1),
      ),
      seedRecords: <FavoriteThreadCacheRecord>[
        _cacheRecord(
          tid: '999',
          title: '旧收藏',
          contentKind: ThreadContentKind.forum,
          workId: 'thread:999',
          detailLoadedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final service = _service(
      remoteRepository: remote,
      localRepository: local,
      detailContextLoader: _contextLoader(
        loadThreadDetail: (tid) async => ApiSuccess(_invalidDetailForTid(tid)),
      ),
      detailBatchLimit: 10,
    );

    final result = await service.syncRecentlyAddedThread(tid: '404');

    expect(result.failedDetailTids, isEmpty);
    expect(result.detailLoadedCount, 1);
    expect(local.records['404']?.detailState, FavoriteDetailState.invalid);
  });

  test(
    'first sync creates and uses bootstrap governor when snapshot is null',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '漫画'),
          ],
        ),
      });
      final governor = _RecordingGovernor();
      final local = _MemoryLocalFavoriteRepository();
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        governorFactory: () => governor,
        detailBatchLimit: 10,
      );

      await service.sync();

      expect(
        governor.kinds,
        containsAll(<FavoriteFirstSyncRequestKind>[
          FavoriteFirstSyncRequestKind.favoriteListPage,
          FavoriteFirstSyncRequestKind.favoriteThreadDetail,
        ]),
      );
    },
  );

  test('incremental sync is also governed when snapshot exists', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 1,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '漫画'),
        ],
      ),
    });
    final local = _MemoryLocalFavoriteRepository(
      snapshot: FavoriteSyncSnapshot(
        syncKey: favoriteSyncKey,
        remoteCount: 1,
        localActiveCount: 1,
        lastSyncedAt: DateTime(2026, 1, 1),
      ),
      seedRecords: <FavoriteThreadCacheRecord>[
        _cacheRecord(
          tid: '100',
          title: '漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:100',
          detailLoadedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    var created = 0;
    final service = _service(
      remoteRepository: remote,
      localRepository: local,
      governorFactory: () {
        created++;
        return _RecordingGovernor();
      },
      detailBatchLimit: 10,
    );

    await service.sync();

    // Subsequent (incremental) sync must be paced too, to avoid IP bans:
    // it creates a governor and routes the favorite list request through it.
    expect(created, 1);
  });

  test(
    'syncRecentlyAddedThread is governed (paced) even when snapshot is null',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '漫画'),
          ],
        ),
      });
      final governor = _RecordingGovernor();
      final service = _service(
        remoteRepository: remote,
        localRepository: _MemoryLocalFavoriteRepository(),
        governorFactory: () => governor,
        detailBatchLimit: 10,
      );

      await service.syncRecentlyAddedThread(tid: '100');

      // Manual recent-add must also be paced through the governor.
      expect(
        governor.kinds,
        containsAll(<FavoriteFirstSyncRequestKind>[
          FavoriteFirstSyncRequestKind.favoriteListPage,
          FavoriteFirstSyncRequestKind.favoriteThreadDetail,
        ]),
      );
    },
  );

  test(
    'concurrent first sync joins single inflight run and governor',
    () async {
      final remote = _DelayedFavoriteRepository(
        <int, FavoriteThreadDirectoryData>{
          1: _page(
            page: 1,
            totalCount: 1,
            items: <FavoriteThreadReference>[
              _favoriteThread(tid: '100', title: '漫画'),
            ],
          ),
        },
      );
      var governorCreated = 0;
      final governor = _RecordingGovernor();
      final service = _service(
        remoteRepository: remote,
        localRepository: _MemoryLocalFavoriteRepository(),
        governorFactory: () {
          governorCreated++;
          return governor;
        },
        detailBatchLimit: 10,
      );

      final first = service.sync();
      await remote.firstRequestStarted;
      final second = service.sync();
      remote.release();

      await Future.wait(<Future<FavoriteSyncResult>>[first, second]);

      expect(remote.requestedPages, <int>[1]);
      expect(governorCreated, 1);
      expect(
        governor.kinds
            .where(
              (kind) => kind == FavoriteFirstSyncRequestKind.favoriteListPage,
            )
            .length,
        1,
      );
    },
  );

  test('sync starts a new run after previous inflight settles', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 1,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '漫画'),
        ],
      ),
    });
    final service = _service(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      detailBatchLimit: 10,
    );

    await service.sync();
    await service.sync();

    expect(remote.requestedPages, <int>[1, 1]);
  });

  test('remote list failure fails sync before detail ingestion', () async {
    final local = _MemoryLocalFavoriteRepository();
    final comicIngest = _FakeComicIngestService();
    final novelIngest = _FakeNovelIngestService();
    var detailLoadCount = 0;
    final service = _service(
      remoteRepository: const _FailingFavoriteRepository('远端失败'),
      localRepository: local,
      detailContextLoader: _contextLoader(
        loadThreadDetail: (tid) async {
          detailLoadCount++;
          return ApiSuccess(_detailForTid(tid));
        },
      ),
      comicIngestService: comicIngest,
      novelIngestService: novelIngest,
    );

    await expectLater(
      service.sync(),
      throwsA(
        isA<StateError>().having((error) => error.message, 'message', '远端失败'),
      ),
    );

    expect(detailLoadCount, 0);
    expect(comicIngest.upsertedTids, isEmpty);
    expect(novelIngest.upsertedTids, isEmpty);
    expect(local.syncFailureMessages, <String>['远端失败']);
  });

  test(
    'count decrease does full diff and removes disappeared module shelf items',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '保留'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository(
        snapshot: FavoriteSyncSnapshot(
          syncKey: favoriteSyncKey,
          remoteCount: 2,
          localActiveCount: 2,
          lastSyncedAt: DateTime(2026, 1, 1),
        ),
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '100',
            title: '保留',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:100',
          ),
          _cacheRecord(
            tid: '200',
            title: '移除',
            contentKind: ThreadContentKind.novel,
            workId: 'novel:49:200',
          ),
        ],
      );
      final novelIngest = _FakeNovelIngestService();
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: novelIngest,
        detailBatchLimit: 10,
      );

      final result = await service.sync();

      expect(result.mode, FavoriteSyncMode.fullDiff);
      expect(result.removedRecords.map((record) => record.tid), <String>[
        '200',
      ]);
      expect(novelIngest.removedWorkIds, <String>['novel:49:200']);
    },
  );

  test(
    'removes disappeared shelf items via content ingest registry handlers',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 0,
          items: const <FavoriteThreadReference>[],
        ),
      });
      final local = _MemoryLocalFavoriteRepository(
        snapshot: FavoriteSyncSnapshot(
          syncKey: favoriteSyncKey,
          remoteCount: 1,
          localActiveCount: 1,
          lastSyncedAt: DateTime(2026, 1, 1),
        ),
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '100',
            title: '移除漫画',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:100',
            detailLoadedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final comicHandler = _SpyFavoriteContentIngestHandler(
        kind: ThreadContentKind.comic,
      );
      final registry = _SpyFavoriteContentIngestRegistry(
        comicHandler: comicHandler,
        novelHandler: _SpyFavoriteContentIngestHandler(
          kind: ThreadContentKind.novel,
        ),
        forumHandler: _SpyFavoriteContentIngestHandler(
          kind: ThreadContentKind.forum,
        ),
      );
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        contentIngestRegistry: registry,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) =>
              throw StateError('detail should not be loaded during removal'),
        ),
        detailBatchLimit: 10,
      );

      await service.sync();

      expect(registry.requestedKinds, contains(ThreadContentKind.comic));
      expect(comicHandler.removedWorkIds, <String>['yamibo:100']);
    },
  );

  test('writes handler returned work id back to local favorite meta', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 1,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '漫画'),
        ],
      ),
    });
    final local = _MemoryLocalFavoriteRepository();
    final comicHandler = _SpyFavoriteContentIngestHandler(
      kind: ThreadContentKind.comic,
      ingestWorkIdBuilder: (request) => 'merged:${request.context.detail.tid}',
    );
    final registry = _SpyFavoriteContentIngestRegistry(
      comicHandler: comicHandler,
      novelHandler: _SpyFavoriteContentIngestHandler(
        kind: ThreadContentKind.novel,
      ),
      forumHandler: _SpyFavoriteContentIngestHandler(
        kind: ThreadContentKind.forum,
      ),
    );
    final service = _service(
      remoteRepository: remote,
      localRepository: local,
      contentIngestRegistry: registry,
      detailContextLoader: _contextLoader(),
      detailBatchLimit: 10,
    );

    final result = await service.sync();

    expect(result.detailLoadedCount, 1);
    expect(comicHandler.ingestedTids, <String>['100']);
    expect(local.records['100']?.workId, 'merged:100');
    expect(local.records['100']?.contentKind, ThreadContentKind.comic);
  });

  test(
    'detail failure does not block following missing records in same sync',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 2,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '坏记录'),
            _favoriteThread(tid: '200', title: '小说'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository();
      final novelIngest = _FakeNovelIngestService();
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) async {
            if (tid == '100') {
              return const ApiFailure<ThreadDetailData>(
                ApiError(type: ApiErrorType.network, message: '网络错误'),
              );
            }
            return ApiSuccess(_detailForTid(tid));
          },
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: novelIngest,
        detailBatchLimit: 1,
      );

      final result = await service.sync();

      expect(result.failedDetailTids, <String>['100']);
      expect(result.detailLoadedCount, 1);
      expect(novelIngest.upsertedTids, <String>['200']);
      expect(local.records['100']?.detailLoadedAt, isNull);
      expect(local.records['200']?.detailLoadedAt, isNotNull);
    },
  );

  test(
    'novel metadata ingest failure remains missing and retries next sync',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '200', title: '小说'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository();
      final novelIngest = _FakeNovelIngestService(
        error: const FormatException('publisher id missing'),
      );
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        novelIngestService: novelIngest,
      );

      final first = await service.sync();
      final second = await service.sync();

      expect(first.failedDetailTids, <String>['200']);
      expect(second.failedDetailTids, <String>['200']);
      expect(local.records['200']?.detailLoadedAt, isNull);
      expect(novelIngest.upsertedTids, <String>['200', '200']);
    },
  );

  test('emits list and detail progress during first full sync', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 3,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '漫画'),
          _favoriteThread(tid: '200', title: '小说'),
        ],
      ),
      2: _page(
        page: 2,
        totalCount: 3,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '300', title: '普通帖'),
        ],
      ),
    });
    final service = _service(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      detailContextLoader: _contextLoader(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: _FakeNovelIngestService(),
      detailBatchLimit: 10,
    );
    final emitted = <FavoriteSyncProgress>[];
    void listener() {
      emitted.add(service.progress.value);
    }

    service.progress.addListener(listener);
    addTearDown(() => service.progress.removeListener(listener));

    await service.sync();

    expect(
      emitted.map((progress) => progress.phase),
      containsAll(<FavoriteSyncProgressPhase>[
        FavoriteSyncProgressPhase.fetchingList,
        FavoriteSyncProgressPhase.savingList,
        FavoriteSyncProgressPhase.loadingDetails,
        FavoriteSyncProgressPhase.completed,
      ]),
    );
    expect(
      emitted.any(
        (progress) =>
            progress.phase == FavoriteSyncProgressPhase.fetchingList &&
            progress.total == 2,
      ),
      isTrue,
    );
    final parsingProgress = emitted
        .where(
          (progress) =>
              progress.phase == FavoriteSyncProgressPhase.loadingDetails &&
              progress.subject == '漫画',
        )
        .toList(growable: false);
    expect(parsingProgress.first.subject, '漫画');
    expect(parsingProgress.first.current, 1);
    expect(parsingProgress.first.total, 3);
    expect(service.progress.value.isActive, isFalse);
  });

  test('novel metadata ingest notifies novel and favorite shelves', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 1,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '200', title: '小说'),
        ],
      ),
    });
    final novelIngest = _FakeNovelIngestService();
    final bus = LibraryShelfRefreshBus();
    addTearDown(bus.dispose);
    final signals = <LibraryShelfRefreshSignal>[];
    bus.signal.addListener(() {
      final signal = bus.signal.value;
      if (signal != null) {
        signals.add(signal);
      }
    });
    final service = _service(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      detailContextLoader: _contextLoader(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: novelIngest,
      shelfRefreshBus: bus,
      detailBatchLimit: 10,
    );

    await service.sync();

    expect(novelIngest.upsertedTids, <String>['200']);
    expect(
      signals.any(
        (signal) =>
            signal.reason == 'favorite_novel_refresh_completed' &&
            signal.modules.contains(LibraryModuleKey.novel) &&
            signal.modules.contains(LibraryModuleKey.favorite) &&
            signal.source == LibraryMutationSource.novelRefresh &&
            signal.workId == 'novel:49:200' &&
            signal.tid == '200',
      ),
      isTrue,
    );
    expect(bus.signal.value?.reason, 'favorite_sync_completed');
    expect(bus.signal.value?.source, LibraryMutationSource.favoriteSync);
    expect(bus.signal.value?.payload['upsertedCount'], 1);
    expect(bus.signal.value?.payload['removedCount'], 0);
    expect(bus.signal.value?.payload['detailLoadedCount'], 1);
  });

  test(
    'first sync queues catalog miss search when comic tag is long-running',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '[Fav] Long Comic EP 02'),
          ],
        ),
      });
      final queue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final signals = <LibraryShelfRefreshSignal>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          signals.add(signal);
        }
      });
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
          searchOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.search,
            links: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-201-1-1.html',
                rawText: 'Episode 2',
              ),
            ],
            usedSearch: true,
          ),
        ),
        searchQueue: queue,
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final service = _service(
        remoteRepository: remote,
        localRepository: _MemoryLocalFavoriteRepository(),
        detailContextLoader: _contextLoader(
          loadTagLookup: () async => _lookup(comicTagName: _longRunningTagName),
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
        detailBatchLimit: 10,
      );

      await service.sync();

      // 旧路径在 bootstrapInitial 下走内联搜索；新路径下所有 catalog 未命中
      // 都走持久化等待队列，由 ForumSearchScheduler 控制节奏，并通过队列快照
      // 驱动通知栏。
      expect(queue.enqueuedRequests, hasLength(1));
      expect(
        signals.any(
          (signal) => signal.reason == 'favorite_comic_search_refresh_queued',
        ),
        isTrue,
      );
      expect(
        signals.any(
          (signal) =>
              signal.reason == 'favorite_comic_catalog_miss_search_skipped',
        ),
        isFalse,
      );
    },
  );

  test(
    'first sync skips catalog miss search for non long-running comic tag',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '[Fav] Short Comic EP 02'),
          ],
        ),
      });
      final queue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        ),
        searchQueue: queue,
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final service = _service(
        remoteRepository: remote,
        localRepository: _MemoryLocalFavoriteRepository(),
        detailContextLoader: _contextLoader(),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
        detailBatchLimit: 10,
      );

      await service.sync();

      expect(queue.enqueuedRequests, isEmpty);
    },
  );

  test(
    'comic auto refresh failure still marks favorite detail loaded',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '漫画'),
          ],
        ),
      });
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: const _ThrowingRefreshService(),
        searchQueue: _RecordingSearchQueue(),
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final local = _MemoryLocalFavoriteRepository();
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
        detailBatchLimit: 10,
      );

      final result = await service.sync();

      expect(result.detailLoadedCount, 1);
      expect(local.records['100']?.contentKind, ThreadContentKind.comic);
      expect(local.records['100']?.workId, 'yamibo:100');
      expect(local.records['100']?.detailLoadedAt, isNotNull);
    },
  );

  test(
    'background maintenance queues already-loaded comic favorites for auto refresh',
    () async {
      final local = _MemoryLocalFavoriteRepository(
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '100',
            title: '[Fav] Backfill Comic EP 02',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:100',
            detailLoadedAt: DateTime(2026, 1, 1),
            sourceTagName: _longRunningTagName,
          ),
        ],
      );
      final queue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        ),
        searchQueue: queue,
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final service = _service(
        remoteRepository: _FakeFavoriteRepository(
          const <int, FavoriteThreadDirectoryData>{},
        ),
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) =>
              throw StateError('detail should not be loaded'),
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
      );

      await service.runBackgroundMaintenance();

      expect(queue.enqueuedTitles, <String>['Backfill Comic']);
      expect(queue.enqueuedRequests.single.comicId, 'yamibo:100');
      expect(queue.enqueuedRequests.single.sourceTid, '100');
      expect(queue.enqueuedRequests.single.displayTitle, 'Backfill Comic');
      expect(queue.enqueuedRequests.single.sourceTitle, 'Backfill Comic');
      expect(await local.hasCompletedComicAutoRefreshBackfill(), isTrue);
    },
  );

  test(
    'background maintenance queues long-running comic by type id when tag name is missing',
    () async {
      final local = _MemoryLocalFavoriteRepository(
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '100',
            title: '[Fav] Long Running Backfill EP 02',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:100',
            sourceFid: '30',
            sourceTypeid: '69',
            sourceTagName: null,
            detailLoadedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final queue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        ),
        searchQueue: queue,
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final service = _service(
        remoteRepository: _FakeFavoriteRepository(
          const <int, FavoriteThreadDirectoryData>{},
        ),
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) =>
              throw StateError('detail should not be loaded'),
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
      );

      await service.runBackgroundMaintenance();

      expect(queue.enqueuedRequests, hasLength(1));
      expect(queue.enqueuedRequests.single.comicId, 'yamibo:100');
      expect(queue.enqueuedRequests.single.sourceTid, '100');
    },
  );

  test(
    'background maintenance leaves backfill unfinished when runner cannot execute backfill task',
    () async {
      final local = _MemoryLocalFavoriteRepository(
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '100',
            title: '[Fav] Backfill Comic EP 02',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:100',
            detailLoadedAt: DateTime(2026, 1, 1),
            sourceTagName: _longRunningTagName,
          ),
        ],
      );
      final service = _service(
        remoteRepository: _FakeFavoriteRepository(
          const <int, FavoriteThreadDirectoryData>{},
        ),
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) =>
              throw StateError('detail should not be loaded'),
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        // Intentionally omit comicAutoRefreshCoordinator so the default runner
        // cannot execute ComicAutoRefreshBackfillTask.
      );

      await service.runBackgroundMaintenance();

      expect(await local.hasCompletedComicAutoRefreshBackfill(), isFalse);
    },
  );

  test(
    'background maintenance leaves backfill unfinished when no candidates exist',
    () async {
      final local = _MemoryLocalFavoriteRepository();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        ),
        searchQueue: _RecordingSearchQueue(),
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final service = _service(
        remoteRepository: _FakeFavoriteRepository(
          const <int, FavoriteThreadDirectoryData>{},
        ),
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) =>
              throw StateError('detail should not be loaded'),
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
      );

      await service.runBackgroundMaintenance();

      expect(await local.hasCompletedComicAutoRefreshBackfill(), isFalse);
    },
  );

  test('writes favorites snapshot to download storage after sync', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 1,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '漫画'),
        ],
      ),
    });
    final storage = _FavoriteSnapshotStorageSpy();
    final service = _service(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      detailContextLoader: _contextLoader(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: _FakeNovelIngestService(),
      downloadStorageService: storage,
      detailBatchLimit: 10,
    );

    await service.sync();

    expect(storage.snapshot?['remoteCount'], 1);
    final threads = storage.snapshot?['threads'] as List<dynamic>;
    expect(threads.single['tid'], '100');
    expect(threads.single['contentKind'], 'comic');
  });

  test(
    'first full sync runs comic duplicate merge once after details load',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '漫画'),
          ],
        ),
      });
      final duplicateRepository = _FakeDuplicateMergeRepository(
        groups: const <ComicDuplicateGroup>[
          ComicDuplicateGroup(
            comicIds: <String>{'yamibo:100', 'yamibo:old'},
            sharedTids: <String>{'100'},
          ),
        ],
      );
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final reasons = <String>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          reasons.add(signal.reason);
        }
      });
      final service = _service(
        remoteRepository: remote,
        localRepository: _MemoryLocalFavoriteRepository(),
        detailContextLoader: _contextLoader(),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicDuplicateMergeService: ComicDuplicateMergeService(
          repository: duplicateRepository,
        ),
        shelfRefreshBus: bus,
        detailBatchLimit: 10,
      );

      await service.sync();

      expect(duplicateRepository.mergeAllCallCount, 2);
      expect(duplicateRepository.mergeComicIds, isEmpty);
      expect(
        reasons,
        contains('favorite_first_sync_comic_duplicate_merge_completed'),
      );
      expect(bus.signal.value?.reason, 'favorite_sync_completed');
      expect(bus.signal.value?.source, LibraryMutationSource.favoriteSync);
    },
  );

  test('incremental comic detail stores merged target work id', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 2,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '新增漫画'),
          _favoriteThread(tid: '999', title: '旧收藏'),
        ],
      ),
    });
    final local = _MemoryLocalFavoriteRepository(
      snapshot: FavoriteSyncSnapshot(
        syncKey: favoriteSyncKey,
        remoteCount: 1,
        localActiveCount: 1,
        lastSyncedAt: DateTime(2026, 1, 1),
      ),
      seedRecords: <FavoriteThreadCacheRecord>[
        _cacheRecord(
          tid: '999',
          title: '旧收藏',
          contentKind: ThreadContentKind.forum,
          workId: 'thread:999',
          detailLoadedAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final duplicateRepository = _FakeDuplicateMergeRepository(
      groups: const <ComicDuplicateGroup>[
        ComicDuplicateGroup(
          comicIds: <String>{'yamibo:100', 'yamibo:old'},
          sharedTids: <String>{'100'},
        ),
      ],
    );
    final service = _service(
      remoteRepository: remote,
      localRepository: local,
      detailContextLoader: _contextLoader(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: _FakeNovelIngestService(),
      comicDuplicateMergeService: ComicDuplicateMergeService(
        repository: duplicateRepository,
      ),
      detailBatchLimit: 10,
    );

    final result = await service.sync();

    expect(result.mode, FavoriteSyncMode.incremental);
    expect(duplicateRepository.mergeAllCallCount, 0);
    expect(duplicateRepository.mergeComicIds, <String>['yamibo:100']);
    expect(local.records['100']?.workId, 'yamibo:old');
  });

  test(
    'incremental comic detail keeps ingested work id when duplicate merge fails',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 2,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '新增漫画'),
            _favoriteThread(tid: '999', title: '旧收藏'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository(
        snapshot: FavoriteSyncSnapshot(
          syncKey: favoriteSyncKey,
          remoteCount: 1,
          localActiveCount: 1,
          lastSyncedAt: DateTime(2026, 1, 1),
        ),
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '999',
            title: '旧收藏',
            contentKind: ThreadContentKind.forum,
            workId: 'thread:999',
            detailLoadedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicDuplicateMergeService: const ComicDuplicateMergeService(
          repository: _ThrowingDuplicateMergeRepository(),
        ),
        detailBatchLimit: 10,
      );

      final result = await service.sync();

      expect(result.detailLoadedCount, 1);
      expect(local.records['100']?.workId, 'yamibo:100');
      expect(local.records['100']?.detailLoadedAt, isNotNull);
    },
  );

  test(
    'recently added comic sync refreshes target thread and queues search on catalog miss',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 2,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '新收藏漫画'),
            _favoriteThread(tid: '999', title: '旧收藏'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository(
        snapshot: FavoriteSyncSnapshot(
          syncKey: favoriteSyncKey,
          remoteCount: 1,
          localActiveCount: 1,
          lastSyncedAt: DateTime(2026, 1, 1),
        ),
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '999',
            title: '旧收藏',
            contentKind: ThreadContentKind.forum,
            workId: 'thread:999',
            detailLoadedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final queue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final reasons = <String>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          reasons.add(signal.reason);
        }
      });
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        ),
        searchQueue: queue,
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
        shelfRefreshBus: bus,
        detailBatchLimit: 10,
      );

      final result = await service.syncRecentlyAddedThread(tid: '100');

      expect(result.detailLoadedCount, 1);
      expect(queue.enqueuedRequests.single.comicId, 'yamibo:100');
      expect(local.records['100']?.contentKind, ThreadContentKind.comic);
      expect(local.records['100']?.detailLoadedAt, isNotNull);
      expect(reasons, contains('favorite_comic_search_refresh_queued'));
      expect(reasons, contains('thread_favorite_recent_sync_completed'));
      expect(bus.signal.value?.source, LibraryMutationSource.favoriteSync);
      expect(bus.signal.value?.payload['upsertedCount'], 2);
      expect(bus.signal.value?.payload['detailLoadedCount'], 1);
    },
  );

  test(
    'recently added sync seeds target from detail when favorite list lags',
    () async {
      final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '999', title: '旧收藏'),
          ],
        ),
      });
      final local = _MemoryLocalFavoriteRepository(
        snapshot: FavoriteSyncSnapshot(
          syncKey: favoriteSyncKey,
          remoteCount: 1,
          localActiveCount: 1,
          lastSyncedAt: DateTime(2026, 1, 1),
        ),
        seedRecords: <FavoriteThreadCacheRecord>[
          _cacheRecord(
            tid: '999',
            title: '旧收藏',
            contentKind: ThreadContentKind.forum,
            workId: 'thread:999',
            detailLoadedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final queue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: _BackfillRefreshService(
          catalogOutcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        ),
        searchQueue: queue,
        refreshOutcomeApplier: _defaultRefreshOutcomeApplier(bus),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );
      var detailLoadCount = 0;
      final service = _service(
        remoteRepository: remote,
        localRepository: local,
        detailContextLoader: _contextLoader(
          loadThreadDetail: (tid) async {
            detailLoadCount++;
            return ApiSuccess(_detailForTid(tid));
          },
        ),
        comicIngestService: _FakeComicIngestService(),
        novelIngestService: _FakeNovelIngestService(),
        comicAutoRefreshCoordinator: coordinator,
        shelfRefreshBus: bus,
        detailBatchLimit: 10,
      );

      final result = await service.syncRecentlyAddedThread(tid: '100');

      expect(remote.requestedPages, <int>[1]);
      expect(detailLoadCount, 1);
      expect(result.detailLoadedCount, 1);
      expect(local.records['100']?.title, '主题100');
      expect(local.records['100']?.remoteFavoriteId, isNull);
      expect(local.records['100']?.favoritedAt, isNull);
      expect(local.records['100']?.contentKind, ThreadContentKind.comic);
      expect(local.records['100']?.detailLoadedAt, isNotNull);
      expect(queue.enqueuedRequests.single.comicId, 'yamibo:100');
    },
  );

  test('capability insufficiency fails before thread cache mutation', () async {
    final remote = _InsufficientCapabilityFavoriteRepository(
      <int, FavoriteThreadDirectoryData>{
        1: _page(
          page: 1,
          totalCount: 1,
          items: <FavoriteThreadReference>[
            _favoriteThread(tid: '100', title: '主题'),
          ],
        ),
      },
    );
    final local = _MemoryLocalFavoriteRepository();
    final service = _service(remoteRepository: remote, localRepository: local);

    await expectLater(service.sync(), throwsStateError);

    expect(local.upsertCallCount, 0);
    expect(local.markRemovedCallCount, 0);
    expect(local.records, isEmpty);
  });

  test('cross-page duplicate tid fails before thread cache mutation', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 3,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '主题一'),
          _favoriteThread(tid: '200', title: '主题二'),
        ],
      ),
      2: _page(
        page: 2,
        totalCount: 3,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '200', title: '重复主题'),
        ],
      ),
    });
    final local = _MemoryLocalFavoriteRepository();
    final service = _service(remoteRepository: remote, localRepository: local);

    await expectLater(service.sync(), throwsStateError);

    expect(local.upsertCallCount, 0);
    expect(local.markRemovedCallCount, 0);
    expect(local.records, isEmpty);
  });

  test('pagination drift fails before thread cache mutation', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadDirectoryData>{
      1: _page(
        page: 1,
        totalCount: 3,
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '100', title: '主题一'),
          _favoriteThread(tid: '200', title: '主题二'),
        ],
      ),
      2: FavoriteThreadDirectoryData(
        items: <FavoriteThreadReference>[
          _favoriteThread(tid: '300', title: '主题三'),
        ],
        pagination: const FavoriteThreadPagination(
          currentPage: 2,
          pageSize: 3,
          totalItems: 3,
          totalPages: 1,
          hasPrevious: true,
          hasNext: false,
        ),
      ),
    });
    final local = _MemoryLocalFavoriteRepository();
    final service = _service(remoteRepository: remote, localRepository: local);

    await expectLater(service.sync(), throwsStateError);

    expect(local.upsertCallCount, 0);
    expect(local.markRemovedCallCount, 0);
    expect(local.records, isEmpty);
  });
}

NetworkFavoriteSyncService _service({
  required FavoriteThreadDirectoryRepository remoteRepository,
  required LocalFavoriteRepository localRepository,
  FavoriteDetailContextLoader? detailContextLoader,
  ComicFavoriteIngestService? comicIngestService,
  NovelFavoriteIngestService? novelIngestService,
  FavoriteContentIngestRegistry? contentIngestRegistry,
  LibraryPostIngestTaskRunner? postIngestTaskRunner,
  ComicFavoriteAutoRefreshCoordinator? comicAutoRefreshCoordinator,
  ComicDuplicateMergeService? comicDuplicateMergeService,
  LibraryShelfRefreshBus? shelfRefreshBus,
  DownloadStorageService? downloadStorageService,
  int detailBatchLimit = 20,
  FavoriteFirstSyncRequestGovernor Function()? governorFactory,
}) {
  final resolvedComicIngestService =
      comicIngestService ?? _FakeComicIngestService();
  final resolvedNovelIngestService =
      novelIngestService ?? _FakeNovelIngestService();
  return NetworkFavoriteSyncService(
    remoteRepository: remoteRepository,
    localRepository: localRepository,
    detailContextLoader: detailContextLoader ?? _contextLoader(),
    contentIngestRegistry:
        contentIngestRegistry ??
        _contentRegistry(
          comicIngestService: resolvedComicIngestService,
          novelIngestService: resolvedNovelIngestService,
        ),
    postIngestTaskRunner:
        postIngestTaskRunner ??
        DefaultLibraryPostIngestTaskRunner(
          comicAutoRefreshCoordinator: comicAutoRefreshCoordinator,
          comicDuplicateMergeService: comicDuplicateMergeService,
          shelfRefreshBus: shelfRefreshBus,
        ),
    shelfRefreshBus: shelfRefreshBus,
    downloadStorageService: downloadStorageService,
    detailBatchLimit: detailBatchLimit,
    governorFactory: governorFactory,
  );
}

FavoriteContentIngestRegistry _contentRegistry({
  ComicFavoriteIngestService? comicIngestService,
  NovelFavoriteIngestService? novelIngestService,
}) {
  return DefaultFavoriteContentIngestRegistry(
    comicHandler: ComicFavoriteContentIngestHandler(
      ingestService: comicIngestService ?? _FakeComicIngestService(),
    ),
    novelHandler: NovelFavoriteContentIngestHandler(
      ingestService: novelIngestService ?? _FakeNovelIngestService(),
    ),
    forumHandler: const ForumFavoriteContentIngestHandler(),
  );
}

ComicRefreshOutcomeApplier _defaultRefreshOutcomeApplier(
  LibraryShelfRefreshBus bus,
) {
  return DefaultComicRefreshOutcomeApplier(
    repository: _RecordingComicRepository(),
    firstEpisodeCoverPromoter: _RecordingCoverPromoter(),
    shelfRefreshBus: bus,
  );
}

class _FavoriteSnapshotStorageSpy implements DownloadStorageService {
  Map<String, Object?>? snapshot;

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) async {
    snapshot = json;
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  }) async => null;
  @override
  Future<DownloadStorageRoot> prepareRoot() => throw UnimplementedError();
  @override
  Future<io.Directory> prepareComicDirectory({
    required String workId,
    required String title,
  }) => throw UnimplementedError();
  @override
  Future<bool> deleteComicDownloads({required String workId}) async => false;
  @override
  Future<bool> deleteNovelDownloads({required String novelId}) async => false;
  @override
  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  }) => throw UnimplementedError();
  @override
  String safeFileName(String value, {String fallback = 'untitled'}) => value;
  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) =>
      throw UnimplementedError();
}

class _FakeFavoriteRepository implements FavoriteThreadDirectoryRepository {
  _FakeFavoriteRepository(this.pages);

  final Map<int, FavoriteThreadDirectoryData> pages;
  final List<int> requestedPages = <int>[];

  @override
  FavoriteThreadDirectorySourceCapabilities get capabilities =>
      _testDirectorySourceCapabilities;

  @override
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    requestedPages.add(query.page);
    return DataReadSuccess(
      data:
          pages[query.page] ??
          _page(
            page: query.page,
            totalCount: 0,
            items: const <FavoriteThreadReference>[],
          ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _DelayedFavoriteRepository extends _FakeFavoriteRepository {
  _DelayedFavoriteRepository(super.pages);

  final Completer<void> _firstRequestStarted = Completer<void>();
  final Completer<void> _releaseGate = Completer<void>();

  Future<void> get firstRequestStarted => _firstRequestStarted.future;

  void release() {
    if (!_releaseGate.isCompleted) {
      _releaseGate.complete();
    }
  }

  @override
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    requestedPages.add(query.page);
    if (!_firstRequestStarted.isCompleted) {
      _firstRequestStarted.complete();
    }
    await _releaseGate.future;
    return DataReadSuccess(
      data:
          pages[query.page] ??
          _page(
            page: query.page,
            totalCount: 0,
            items: const <FavoriteThreadReference>[],
          ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _InsufficientCapabilityFavoriteRepository
    extends _FakeFavoriteRepository {
  _InsufficientCapabilityFavoriteRepository(super.pages);

  @override
  FavoriteThreadDirectorySourceCapabilities get capabilities =>
      FavoriteThreadDirectorySourceCapabilities(
        values: DataCapabilitySet<FavoriteThreadDirectoryCapability>.supported(
          FavoriteThreadDirectoryCapability.values.where(
            (capability) =>
                capability != FavoriteThreadDirectoryCapability.totalItemCount,
          ),
        ),
        paginationPrecision: PaginationPrecision.exact,
      );
}

class _FailingFavoriteRepository implements FavoriteThreadDirectoryRepository {
  const _FailingFavoriteRepository(this.message);

  final String message;

  @override
  FavoriteThreadDirectorySourceCapabilities get capabilities =>
      _testDirectorySourceCapabilities;

  @override
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    return DataReadFailure(
      kind: DataReadFailureKind.network,
      diagnosticMessage: message,
    );
  }
}

final _testDirectorySourceCapabilities =
    FavoriteThreadDirectorySourceCapabilities(
      values: DataCapabilitySet<FavoriteThreadDirectoryCapability>.supported(
        FavoriteThreadDirectoryCapability.values,
      ),
      paginationPrecision: PaginationPrecision.exact,
    );

class _FakeComicIngestService implements ComicFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
    String? sourceTagName,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    upsertedTids.add(detail.tid);
    return 'yamibo:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _SpyFavoriteContentIngestRegistry
    implements FavoriteContentIngestRegistry {
  _SpyFavoriteContentIngestRegistry({
    required FavoriteContentIngestHandler comicHandler,
    required FavoriteContentIngestHandler novelHandler,
    required FavoriteContentIngestHandler forumHandler,
  }) : _handlers = <ThreadContentKind, FavoriteContentIngestHandler>{
         ThreadContentKind.comic: comicHandler,
         ThreadContentKind.novel: novelHandler,
         ThreadContentKind.forum: forumHandler,
         ThreadContentKind.unknown: forumHandler,
       };

  final Map<ThreadContentKind, FavoriteContentIngestHandler> _handlers;
  final List<ThreadContentKind> requestedKinds = <ThreadContentKind>[];

  @override
  FavoriteContentIngestHandler handlerFor(ThreadContentKind kind) {
    requestedKinds.add(kind);
    return _handlers[kind] ?? _handlers[ThreadContentKind.forum]!;
  }
}

class _SpyFavoriteContentIngestHandler implements FavoriteContentIngestHandler {
  _SpyFavoriteContentIngestHandler({
    required this.kind,
    this.ingestWorkIdBuilder,
  });

  @override
  final ThreadContentKind kind;

  final String Function(FavoriteContentIngestRequest request)?
  ingestWorkIdBuilder;
  final List<String> ingestedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  ) async {
    ingestedTids.add(request.context.detail.tid);
    return FavoriteContentIngestResult(
      kind: kind,
      workId:
          ingestWorkIdBuilder?.call(request) ??
          'work:${request.context.detail.tid}',
    );
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _FakeNovelIngestService implements NovelFavoriteIngestService {
  _FakeNovelIngestService({this.error});

  final Object? error;
  final List<String> upsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
    String? sourceTagName,
  }) async {
    upsertedTids.add(detail.tid);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return 'novel:${detail.fid}:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _BackfillRefreshService implements ComicEpisodeRefreshService {
  _BackfillRefreshService({
    required ComicEpisodeRefreshOutcome catalogOutcome,
    ComicEpisodeRefreshOutcome? searchOutcome,
  }) : _catalogOutcome = catalogOutcome,
       _searchOutcome = searchOutcome;

  final ComicEpisodeRefreshOutcome _catalogOutcome;
  final ComicEpisodeRefreshOutcome? _searchOutcome;

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    return _catalogOutcome;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _catalogOutcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _catalogOutcome;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return _catalogOutcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(
    String catalogUrl, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    return _searchOutcome ??
        const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        );
  }
}

class _ThrowingRefreshService implements ComicEpisodeRefreshService {
  const _ThrowingRefreshService();

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    throw StateError('refresh failed');
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(
    String catalogUrl, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    throw StateError('refresh failed');
  }
}

class _RecordingGovernor implements FavoriteFirstSyncRequestGovernor {
  final List<FavoriteFirstSyncRequestKind> kinds =
      <FavoriteFirstSyncRequestKind>[];

  @override
  Future<T> run<T>({
    required FavoriteFirstSyncRequestKind kind,
    required Future<T> Function() action,
  }) async {
    kinds.add(kind);
    return action();
  }
}

class _RecordingSearchQueue implements ComicSearchRefreshQueueEnqueuer {
  final List<ComicEpisodeRefreshRequest> enqueuedRequests =
      <ComicEpisodeRefreshRequest>[];
  final List<String> enqueuedTitles = <String>[];

  @override
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
  }) async {
    enqueuedRequests.add(request);
    enqueuedTitles.add(title);
    return ComicSearchRefreshEnqueueResult(
      entry: ComicSearchRefreshQueueEntry(
        id: enqueuedRequests.length,
        comicId: request.comicId ?? '',
        title: title,
        request: request,
        origin: origin,
        status: ComicSearchRefreshQueueStatus.pending,
        attempts: 0,
        availableAt: DateTime(2026, 5, 16),
        createdAt: DateTime(2026, 5, 16),
        updatedAt: DateTime(2026, 5, 16),
      ),
      position: enqueuedRequests.length,
      estimatedDuration: Duration(
        milliseconds: 10500 * enqueuedRequests.length,
      ),
      deduplicated: false,
    );
  }
}

class _RecordingCoverPromoter implements ComicFirstEpisodeCoverPromoter {
  @override
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDiscoveryCache? threadCache,
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    return true;
  }
}

class _RecordingComicRepository implements ComicRepository {
  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return ComicEpisodeRefreshResult(
      insertedCount: episodeLinks.length,
      updatedCount: 0,
      totalCount: episodeLinks.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeDuplicateMergeRepository implements ComicDuplicateMergeRepository {
  _FakeDuplicateMergeRepository({required List<ComicDuplicateGroup> groups})
    : _groups = groups.toList(growable: true);

  final List<ComicDuplicateGroup> _groups;
  final List<String> mergeComicIds = <String>[];
  int mergeAllCallCount = 0;

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({
    String? comicId,
  }) async {
    if (comicId == null || comicId.trim().isEmpty) {
      mergeAllCallCount++;
      return List<ComicDuplicateGroup>.unmodifiable(_groups);
    }
    mergeComicIds.add(comicId.trim());
    return _groups
        .where((group) => group.comicIds.contains(comicId.trim()))
        .toList(growable: false);
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    _groups.removeWhere((group) => group.comicIds.containsAll(comicIds));
    final target = comicIds.contains('yamibo:old')
        ? 'yamibo:old'
        : comicIds.first;
    final removed = comicIds.where((comicId) => comicId != target).toSet();
    return ComicDuplicateMergeResult(
      targetComicId: target,
      targetTitle: '短标题',
      mergedComicIds: removed,
      replacements: <String, String>{
        for (final comicId in removed) comicId: target,
      },
      movedEpisodeCount: 1,
    );
  }
}

class _ThrowingDuplicateMergeRepository
    implements ComicDuplicateMergeRepository {
  const _ThrowingDuplicateMergeRepository();

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) {
    throw StateError('merge failed');
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) {
    throw StateError('merge failed');
  }
}

class _MemoryLocalFavoriteRepository implements LocalFavoriteRepository {
  _MemoryLocalFavoriteRepository({
    FavoriteSyncSnapshot? snapshot,
    List<FavoriteThreadCacheRecord> seedRecords =
        const <FavoriteThreadCacheRecord>[],
  }) : _snapshot = snapshot,
       records = <String, FavoriteThreadCacheRecord>{
         for (final record in seedRecords) record.tid: record,
       };

  FavoriteSyncSnapshot? _snapshot;
  bool _comicBackfillCompleted = false;
  final Map<String, FavoriteThreadCacheRecord> records;
  final List<String> syncFailureMessages = <String>[];
  int upsertCallCount = 0;
  int markRemovedCallCount = 0;

  @override
  Future<int> countActiveThreads() async =>
      records.values.where((record) => record.isActive).length;

  @override
  Future<int> countMissingDetailRecords() async {
    return records.values
        .where(
          (record) =>
              record.isActive &&
              record.detailState == FavoriteDetailState.pending,
        )
        .length;
  }

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
  }) async {
    _snapshot = FavoriteSyncSnapshot(
      syncKey: favoriteSyncKey,
      remoteCount: remoteCount,
      localActiveCount: await countActiveThreads(),
      lastSyncedAt: DateTime(2026, 1, 1),
      status: status,
      message: message,
    );
  }

  @override
  Future<Set<String>> getActiveTids() async {
    return records.values
        .where((record) => record.isActive)
        .map((record) => record.tid)
        .toSet();
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async {
    return records.values
        .where((record) => record.isActive)
        .toList(growable: false);
  }

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async {
    return _comicBackfillCompleted;
  }

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {
    _comicBackfillCompleted = true;
  }

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async =>
      records[tid];

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async {
    return records.values
        .where((record) => record.isActive && record.workId == workId)
        .toList(growable: false);
  }

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async {
    return records.values.any(
      (record) => record.isActive && record.workId == workId,
    );
  }

  @override
  Future<int> markRemovedByWorkId(String workId) async {
    var changed = 0;
    for (final record in records.values.toList(growable: false)) {
      if (!record.isActive || record.workId != workId) {
        continue;
      }
      records[record.tid] = _cacheRecord(
        tid: record.tid,
        title: record.title,
        contentKind: record.contentKind,
        workId: record.workId,
        sourceTagName: record.sourceTagName,
        detailLoadedAt: record.detailLoadedAt,
        detailState: record.detailState,
        removedAt: DateTime(2026, 1, 2),
      );
      changed++;
    }
    return changed;
  }

  @override
  Future<int> markRemovedByTids(Set<String> tids) async {
    var changed = 0;
    for (final tid in tids) {
      final record = records[tid];
      if (record == null || !record.isActive) {
        continue;
      }
      records[record.tid] = _cacheRecord(
        tid: record.tid,
        title: record.title,
        contentKind: record.contentKind,
        workId: record.workId,
        sourceTagName: record.sourceTagName,
        detailLoadedAt: record.detailLoadedAt,
        detailState: record.detailState,
        removedAt: DateTime(2026, 1, 2),
      );
      changed++;
    }
    return changed;
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return records.values
        .where(
          (record) =>
              record.isActive &&
              record.detailState == FavoriteDetailState.pending &&
              !excludedTids.contains(record.tid),
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return records.values
        .where(
          (record) =>
              record.isActive &&
              record.contentKind == ThreadContentKind.comic &&
              record.workId != null &&
              record.workId!.trim().isNotEmpty &&
              !excludedTids.contains(record.tid),
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(
    String workId,
  ) async => null;

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => _snapshot;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async =>
      const <LibraryWorkItem>[];

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async =>
      const <LibraryCategory>[];

  @override
  Future<void> markSyncFailure(String message) async {
    syncFailureMessages.add(message);
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async {
    markRemovedCallCount += 1;
    final removed = records.values
        .where(
          (record) => record.isActive && !activeRemoteTids.contains(record.tid),
        )
        .toList(growable: false);
    for (final record in removed) {
      records[record.tid] = FavoriteThreadCacheRecord(
        tid: record.tid,
        remoteFavoriteId: record.remoteFavoriteId,
        title: record.title,
        description: record.description,
        authorName: record.authorName,
        replyCount: record.replyCount,
        favoritedAt: record.favoritedAt,
        remoteOrder: record.remoteOrder,
        sourceFid: record.sourceFid,
        sourceTypeid: record.sourceTypeid,
        sourceTagName: record.sourceTagName,
        contentKind: record.contentKind,
        workId: record.workId,
        detailLoadedAt: record.detailLoadedAt,
        detailState: record.detailState,
        firstSeenAt: record.firstSeenAt,
        lastSeenAt: record.lastSeenAt,
        removedAt: DateTime(2026, 1, 2),
        customCategoryId: record.customCategoryId,
      );
    }
    return removed;
  }

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
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {
    final old = records[tid]!;
    records[tid] = FavoriteThreadCacheRecord(
      tid: tid,
      remoteFavoriteId: old.remoteFavoriteId,
      title: old.title,
      description: old.description,
      authorName: old.authorName,
      replyCount: old.replyCount,
      favoritedAt: old.favoritedAt,
      remoteOrder: old.remoteOrder,
      sourceFid: fid,
      sourceTypeid: typeid,
      sourceTagName: tagName,
      contentKind: contentKind,
      workId: workId,
      detailLoadedAt: DateTime(2026, 1, 1),
      detailState: FavoriteDetailState.resolved,
      firstSeenAt: old.firstSeenAt,
      lastSeenAt: old.lastSeenAt,
      removedAt: old.removedAt,
      customCategoryId: old.customCategoryId,
    );
  }

  @override
  Future<void> markThreadDetailInvalid({required String tid}) async {
    final old = records[tid]!;
    records[tid] = FavoriteThreadCacheRecord(
      tid: tid,
      remoteFavoriteId: old.remoteFavoriteId,
      title: old.title,
      description: old.description,
      authorName: old.authorName,
      replyCount: old.replyCount,
      favoritedAt: old.favoritedAt,
      remoteOrder: old.remoteOrder,
      sourceFid: old.sourceFid,
      sourceTypeid: old.sourceTypeid,
      sourceTagName: old.sourceTagName,
      contentKind: ThreadContentKind.unknown,
      workId: old.workId,
      detailLoadedAt: DateTime(2026, 1, 1),
      detailState: FavoriteDetailState.invalid,
      firstSeenAt: old.firstSeenAt,
      lastSeenAt: old.lastSeenAt,
      removedAt: old.removedAt,
      customCategoryId: old.customCategoryId,
    );
  }

  @override
  Future<int> upsertRemoteThreads(List<FavoriteThreadCacheUpsert> items) async {
    upsertCallCount += 1;
    final now = DateTime(2026, 1, 1);
    for (final item in items) {
      final old = records[item.tid];
      records[item.tid] = FavoriteThreadCacheRecord(
        tid: item.tid,
        remoteFavoriteId: item.remoteFavoriteId,
        title: item.title,
        description: item.description,
        authorName: item.authorName,
        replyCount: item.replyCount,
        favoritedAt: item.favoritedAt,
        remoteOrder: item.remoteOrder,
        sourceFid: old?.sourceFid,
        sourceTypeid: old?.sourceTypeid,
        sourceTagName: old?.sourceTagName,
        contentKind: old?.contentKind ?? ThreadContentKind.unknown,
        workId: old?.workId,
        detailLoadedAt: old?.detailLoadedAt,
        detailState: old?.detailState ?? FavoriteDetailState.pending,
        firstSeenAt: old?.firstSeenAt ?? now,
        lastSeenAt: now,
        removedAt: null,
        customCategoryId: old?.customCategoryId,
      );
    }
    return items.length;
  }
}

FavoriteThreadDirectoryData _page({
  required int page,
  required int totalCount,
  required List<FavoriteThreadReference> items,
}) {
  const pageSize = 2;
  final totalPages = totalCount == 0 ? 1 : (totalCount / pageSize).ceil();
  return FavoriteThreadDirectoryData(
    items: items,
    pagination: FavoriteThreadPagination(
      currentPage: page,
      pageSize: pageSize,
      totalItems: totalCount,
      totalPages: totalPages,
      hasPrevious: page > 1,
      hasNext: page < totalPages,
    ),
  );
}

FavoriteThreadReference _favoriteThread({
  required String tid,
  required String title,
}) {
  return FavoriteThreadReference(
    tid: tid,
    title: title,
    remoteFavoriteId: 'fav-$tid',
    description: '',
    authorName: '作者',
    replyCount: 0,
    favoritedAt: DateTime.fromMillisecondsSinceEpoch(
      1767225600 * Duration.millisecondsPerSecond,
      isUtc: true,
    ),
  );
}

FavoriteThreadCacheRecord _cacheRecord({
  required String tid,
  required String title,
  required ThreadContentKind contentKind,
  String? workId,
  String? sourceFid,
  String? sourceTypeid,
  String? sourceTagName,
  DateTime? detailLoadedAt,
  FavoriteDetailState? detailState,
  DateTime? removedAt,
}) {
  return FavoriteThreadCacheRecord(
    tid: tid,
    remoteFavoriteId: 'fav-$tid',
    title: title,
    replyCount: 0,
    sourceFid: sourceFid,
    sourceTypeid: sourceTypeid,
    sourceTagName: sourceTagName,
    contentKind: contentKind,
    workId: workId,
    detailLoadedAt: detailLoadedAt,
    detailState:
        detailState ??
        (detailLoadedAt == null
            ? FavoriteDetailState.pending
            : FavoriteDetailState.resolved),
    firstSeenAt: DateTime(2026, 1, 1),
    lastSeenAt: DateTime(2026, 1, 1),
    removedAt: removedAt,
  );
}

ThreadDetailData _detailForTid(String tid) {
  final fid = switch (tid) {
    '100' => '30',
    '200' => '49',
    _ => '1',
  };
  final typeid = switch (tid) {
    '100' => '398',
    '200' => '293',
    _ => '',
  };
  return ThreadDetailData(
    tid: tid,
    fid: fid,
    typeid: typeid,
    subject: '主题$tid',
    author: '作者',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: 'p1',
        author: '作者',
        authorId: '1',
        message: '<p>正文</p>',
        number: 1,
        isFirst: true,
        dateline: '2026-01-01',
      ),
    ],
  );
}

ThreadDetailData _invalidDetailForTid(String tid) {
  return ThreadDetailData(
    tid: tid,
    fid: '',
    typeid: '',
    subject: '失效主题$tid',
    author: '',
    replies: 0,
    views: 0,
    currentPage: 1,
    perPage: 20,
    posts: const <ThreadPost>[],
  );
}

ForumTagLookup _lookup({String comicTagName = '韩国漫画'}) {
  return ForumTagLookup(<ForumBoardTagSet>[
    ForumBoardTagSet(
      fid: '30',
      name: '漫画区',
      tags: <ForumTagDefinition>[
        ForumTagDefinition(fid: '30', typeid: '398', name: comicTagName),
      ],
    ),
    const ForumBoardTagSet(
      fid: '49',
      name: '文学区',
      tags: <ForumTagDefinition>[
        ForumTagDefinition(fid: '49', typeid: '293', name: '原创'),
      ],
    ),
  ]);
}

FavoriteDetailContextLoader _contextLoader({
  Future<ApiResult<ThreadDetailData>> Function(String tid)? loadThreadDetail,
  FavoriteTagLookupLoader? loadTagLookup,
}) {
  final loader =
      loadThreadDetail ?? ((tid) async => ApiSuccess(_detailForTid(tid)));
  return DefaultFavoriteDetailContextLoader(
    threadRepository: _FavoriteTestThreadRepository(loader),
    loadTagLookup: loadTagLookup ?? (() async => _lookup()),
    classifier: const ThreadContentClassifier(),
  );
}

final class _FavoriteTestThreadRepository implements ThreadRepository {
  const _FavoriteTestThreadRepository(this.loader);

  final Future<ApiResult<ThreadDetailData>> Function(String tid) loader;

  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    return dataReadResultFromApiResult(
      await loader(tid),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}
