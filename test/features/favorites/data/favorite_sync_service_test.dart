import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('first sync fetches all pages and ingests comic and novel details', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 3, items: <FavoriteThread>[
        _favoriteThread(tid: '100', title: '漫画'),
        _favoriteThread(tid: '200', title: '小说'),
      ]),
      2: _page(page: 2, totalCount: 3, items: <FavoriteThread>[
        _favoriteThread(tid: '300', title: '普通帖'),
      ]),
    });
    final local = _MemoryLocalFavoriteRepository();
    final comicIngest = _FakeComicIngestService();
    final novelIngest = _FakeNovelIngestService();
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: local,
      loadThreadDetail: (tid) async => ApiSuccess(_detailForTid(tid)),
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
      comicIngestService: comicIngest,
      novelIngestService: novelIngest,
      detailBatchLimit: 10,
    );

    final result = await service.sync();

    expect(remote.requestedPages, <int>[1, 2]);
    expect(result.mode, FavoriteSyncMode.fullDiff);
    // detailLoadedCount = classify(3) + ingest(2 comic+novel) = 5
    expect(result.detailLoadedCount, greaterThan(0));
    expect(comicIngest.lightUpsertedTids, <String>['100']);
    expect(novelIngest.lightUpsertedTids, <String>['200']);
    expect(local.records['300']?.contentKind, ThreadContentKind.forum);
  });

  test('count decrease does full diff and removes disappeared module shelf items', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 1, items: <FavoriteThread>[
        _favoriteThread(tid: '100', title: '保留'),
      ]),
    });
    final local = _MemoryLocalFavoriteRepository(
      snapshot: FavoriteSyncSnapshot(
        syncKey: favoriteSyncKey,
        remoteCount: 2,
        localActiveCount: 2,
        lastSyncedAt: DateTime(2026, 1, 1),
      ),
      seedRecords: <FavoriteThreadCacheRecord>[
        _cacheRecord(tid: '100', title: '保留', contentKind: ThreadContentKind.comic, workId: 'yamibo:100'),
        _cacheRecord(tid: '200', title: '移除', contentKind: ThreadContentKind.novel, workId: 'novel:49:200'),
      ],
    );
    final novelIngest = _FakeNovelIngestService();
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: local,
      loadThreadDetail: (tid) async => ApiSuccess(_detailForTid(tid)),
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: novelIngest,
      detailBatchLimit: 10,
    );

    final result = await service.sync();

    expect(result.mode, FavoriteSyncMode.fullDiff);
    expect(result.removedRecords.map((record) => record.tid), <String>['200']);
    // 移除操作通过 _removeModuleShelfItems 调用 removeFromShelf
    expect(novelIngest.removedWorkIds, <String>['novel:49:200']);
  });

  test('detail failure does not block following missing records in same sync', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 2, items: <FavoriteThread>[
        _favoriteThread(tid: '100', title: '坏记录'),
        _favoriteThread(tid: '200', title: '小说'),
      ]),
    });
    final local = _MemoryLocalFavoriteRepository();
    final novelIngest = _FakeNovelIngestService();
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: local,
      loadThreadDetail: (tid) async {
        if (tid == '100') {
          return const ApiFailure<ThreadDetailData>(
            ApiError(type: ApiErrorType.network, message: '网络错误'),
          );
        }
        return ApiSuccess(_detailForTid(tid));
      },
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: novelIngest,
      detailBatchLimit: 1,
    );

    final result = await service.sync();

    expect(result.failedDetailTids, contains('100'));
    // 分类阶段：200 成功；摄入阶段：200 被轻量摄入
    expect(novelIngest.lightUpsertedTids, <String>['200']);
    expect(local.records['100']?.detailLoadedAt, isNull);
    expect(local.records['200']?.detailLoadedAt, isNotNull);
  });

  test('emits list and detail progress during first full sync', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 3, items: <FavoriteThread>[
        _favoriteThread(tid: '100', title: '漫画'),
        _favoriteThread(tid: '200', title: '小说'),
      ]),
      2: _page(page: 2, totalCount: 3, items: <FavoriteThread>[
        _favoriteThread(tid: '300', title: '普通帖'),
      ]),
    });
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      loadThreadDetail: (tid) async => ApiSuccess(_detailForTid(tid)),
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
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
        FavoriteSyncProgressPhase.classifying,
        FavoriteSyncProgressPhase.classified,
        FavoriteSyncProgressPhase.ingesting,
        FavoriteSyncProgressPhase.completed,
      ]),
    );
    expect(
      emitted.any((progress) => progress.phase == FavoriteSyncProgressPhase.fetchingList && progress.total == 2),
      isTrue,
    );
    expect(service.progress.value.isActive, isFalse);
  });

  test('writes favorites snapshot to download storage after sync', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 1, items: <FavoriteThread>[
        _favoriteThread(tid: '100', title: '漫画'),
      ]),
    });
    final storage = _FavoriteSnapshotStorageSpy();
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      loadThreadDetail: (tid) async => ApiSuccess(_detailForTid(tid)),
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
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
}

class _FavoriteSnapshotStorageSpy implements DownloadStorageService {
  Map<String, Object?>? snapshot;

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) async {
    snapshot = json;
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({required String workId, required String title, required String episodeId}) async => null;
  @override
  Future<DownloadedNovelChapter?> findDownloadedNovelChapter({required String novelId, required String title, required String episodeId}) async => null;
  @override
  Future<DownloadStorageRoot> prepareRoot() => throw UnimplementedError();
  @override
  Future<io.Directory> prepareComicDirectory({required String workId, required String title}) => throw UnimplementedError();
  @override
  Future<io.Directory> prepareNovelDirectory({required String novelId, required String title}) => throw UnimplementedError();
  @override
  String numberedFileName({required int index, required String title, required String extension}) => throw UnimplementedError();
  @override
  String safeFileName(String value, {String fallback = 'untitled'}) => value;
  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) => throw UnimplementedError();
}

class _FakeFavoriteRepository implements FavoriteRepository {
  _FakeFavoriteRepository(this.pages);

  final Map<int, FavoriteThreadsPage> pages;
  final List<int> requestedPages = <int>[];

  @override
  Future<ApiResult<FavoriteThreadsPage>> getFavoriteThreads({required int page}) async {
    requestedPages.add(page);
    return ApiSuccess(pages[page] ?? _page(page: page, totalCount: 0, items: const <FavoriteThread>[]));
  }

  @override
  Future<ApiResult<List<FavoriteForum>>> getFavoriteForums() async {
    return const ApiSuccess<List<FavoriteForum>>(<FavoriteForum>[]);
  }
}

class _FakeComicIngestService implements ComicFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> lightUpsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({required ThreadDetailData detail, String? sourceTagName}) async {
    upsertedTids.add(detail.tid);
    return 'yamibo:${detail.tid}';
  }

  @override
  Future<String> lightUpsertFromThreadDetail({required ThreadDetailData detail, String? sourceTagName}) async {
    lightUpsertedTids.add(detail.tid);
    return 'yamibo:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _FakeNovelIngestService implements NovelFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> lightUpsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({required ThreadDetailData detail, String? sourceTagName}) async {
    upsertedTids.add(detail.tid);
    return 'novel:${detail.fid}:${detail.tid}';
  }

  @override
  Future<String> lightUpsertFromThreadDetail({required ThreadDetailData detail, String? sourceTagName}) async {
    lightUpsertedTids.add(detail.tid);
    return 'novel:${detail.fid}:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _MemoryLocalFavoriteRepository implements LocalFavoriteRepository {
  _MemoryLocalFavoriteRepository({
    FavoriteSyncSnapshot? snapshot,
    List<FavoriteThreadCacheRecord> seedRecords = const <FavoriteThreadCacheRecord>[],
  })  : _snapshot = snapshot,
        records = <String, FavoriteThreadCacheRecord>{
          for (final record in seedRecords) record.tid: record,
        };

  FavoriteSyncSnapshot? _snapshot;
  final Map<String, FavoriteThreadCacheRecord> records;

  @override
  Future<int> countActiveThreads() async => records.values.where((record) => record.isActive).length;

  @override
  Future<String> createCategory({required String name}) async => 'custom';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<void> finishSync({required FavoriteSyncMode mode, required int remoteCount, String? status, String? message}) async {
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
    return records.values.where((record) => record.isActive).map((record) => record.tid).toSet();
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async {
    return records.values.where((record) => record.isActive).toList(growable: false);
  }

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async => records[tid];

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return records.values
        .where((record) =>
            record.isActive &&
            record.detailLoadedAt == null &&
            !excludedTids.contains(record.tid))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async => null;

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => _snapshot;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async => const <LibraryWorkItem>[];

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async => const <LibraryCategory>[];

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(Set<String> activeRemoteTids) async {
    final removed = records.values
        .where((record) => record.isActive && !activeRemoteTids.contains(record.tid))
        .toList(growable: false);
    for (final record in removed) {
      records[record.tid] = _cacheRecord(
        tid: record.tid,
        title: record.title,
        contentKind: record.contentKind,
        workId: record.workId,
        removedAt: DateTime(2026, 1, 2),
      );
    }
    return removed;
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getClassifiedModuleRecords() async {
    // 只返回已分类但尚未摄入模块的记录（workId 为空），
    // 避免每次同步都重新摄入已完成的漫画/小说。
    return records.values
        .where((record) => record.isActive &&
            record.detailLoadedAt != null &&
            record.workId == null &&
            (record.contentKind == ThreadContentKind.comic || record.contentKind == ThreadContentKind.novel))
        .toList(growable: false);
  }

  @override
  Future<void> updateThreadWorkId({required String tid, required String? workId}) async {
    final old = records[tid];
    if (old != null) {
      records[tid] = _cacheRecord(
        tid: old.tid,
        title: old.title,
        contentKind: old.contentKind,
        workId: workId,
        detailLoadedAt: old.detailLoadedAt,
      );
    }
  }

  @override
  Future<void> moveThreadToCategory({required String tid, required String toCategoryId}) async {}

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
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

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
    records[tid] = _cacheRecord(
      tid: tid,
      title: old.title,
      contentKind: contentKind,
      workId: workId,
      detailLoadedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<int> upsertRemotePage({required FavoriteThreadsPage page, required int pageStartOrder}) async {
    for (final item in page.items) {
      records[item.tid] = records[item.tid] ??
          _cacheRecord(
            tid: item.tid,
            title: item.title,
            contentKind: ThreadContentKind.forum,
          );
    }
    return page.items.length;
  }
}

FavoriteThreadsPage _page({
  required int page,
  required int totalCount,
  required List<FavoriteThread> items,
}) {
  return FavoriteThreadsPage(page: page, perPage: 2, totalCount: totalCount, items: items);
}

FavoriteThread _favoriteThread({required String tid, required String title}) {
  return FavoriteThread(
    favid: 'fav-$tid',
    tid: tid,
    title: title,
    description: '',
    author: '作者',
    replies: 0,
    url: 'thread-$tid-1-1.html',
    dateline: 1767225600,
  );
}

FavoriteThreadCacheRecord _cacheRecord({
  required String tid,
  required String title,
  required ThreadContentKind contentKind,
  String? workId,
  DateTime? detailLoadedAt,
  DateTime? removedAt,
}) {
  return FavoriteThreadCacheRecord(
    tid: tid,
    favid: 'fav-$tid',
    title: title,
    replies: 0,
    contentKind: contentKind,
    workId: workId,
    detailLoadedAt: detailLoadedAt,
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

ForumTagLookup _lookup() {
  return ForumTagLookup(
    const <ForumBoardTagSet>[
      ForumBoardTagSet(
        fid: '30',
        name: '漫画区',
        tags: <ForumTagDefinition>[
          ForumTagDefinition(fid: '30', typeid: '398', name: '韩国漫画'),
        ],
      ),
      ForumBoardTagSet(
        fid: '49',
        name: '文学区',
        tags: <ForumTagDefinition>[
          ForumTagDefinition(fid: '49', typeid: '293', name: '原创'),
        ],
      ),
    ],
  );
}
