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
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

/// Verifies the three-phase pipeline: classify-only pass, then progressive ingest.
void main() {
  test('pipeline emits classify phase before ingest phase', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 2, items: <FavoriteThread>[
        _favoriteThread(tid: '100', title: '漫画A'),
        _favoriteThread(tid: '200', title: '小说B'),
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
      ingestNotifyBatchSize: 1,
    );

    final phases = <FavoriteSyncProgressPhase>[];
    void listener() {
      final p = service.progress.value;
      if (phases.isEmpty || phases.last != p.phase) {
        phases.add(p.phase);
      }
    }
    service.progress.addListener(listener);
    addTearDown(() => service.progress.removeListener(listener));

    await service.sync();

    // classify must appear before ingest, and classified must appear between them.
    final classifyIndex = phases.indexOf(FavoriteSyncProgressPhase.classifying);
    final classifiedIndex = phases.indexOf(FavoriteSyncProgressPhase.classified);
    final ingestIndex = phases.indexOf(FavoriteSyncProgressPhase.ingesting);
    final completedIndex = phases.indexOf(FavoriteSyncProgressPhase.completed);

    expect(classifyIndex, greaterThan(-1));
    expect(classifiedIndex, greaterThan(classifyIndex));
    expect(ingestIndex, greaterThan(classifiedIndex));
    expect(completedIndex, greaterThan(ingestIndex));
  });

  test('ingestNotifyBatchSize controls progress emission frequency', () async {
    final items = <FavoriteThread>[];
    for (var i = 0; i < 9; i++) {
      final tid = '${100 + i}';
      items.add(_favoriteThread(tid: tid, title: '漫画$i'));
    }
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: items.length, items: items),
    });
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      loadThreadDetail: (tid) async => ApiSuccess(_detailForTid(tid)),
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
      comicIngestService: _FakeComicIngestService(),
      novelIngestService: _FakeNovelIngestService(),
      ingestNotifyBatchSize: 3,
    );

    var ingestEmissionCount = 0;
    void listener() {
      if (service.progress.value.phase == FavoriteSyncProgressPhase.ingesting) {
        ingestEmissionCount++;
      }
    }
    service.progress.addListener(listener);
    addTearDown(() => service.progress.removeListener(listener));

    await service.sync();

    // 9 items, batchSize=3: emissions at 3, 6, 9 + final = 4 ingest emissions
    expect(ingestEmissionCount, 4);
  });

  test('forum-only favorites skip ingest phase entirely', () async {
    final remote = _FakeFavoriteRepository(<int, FavoriteThreadsPage>{
      1: _page(page: 1, totalCount: 1, items: <FavoriteThread>[
        _favoriteThread(tid: '300', title: '普通帖'),
      ]),
    });
    final comicIngest = _FakeComicIngestService();
    final novelIngest = _FakeNovelIngestService();
    final service = NetworkFavoriteSyncService(
      remoteRepository: remote,
      localRepository: _MemoryLocalFavoriteRepository(),
      loadThreadDetail: (tid) async => ApiSuccess(_detailForTid(tid)),
      loadTagLookup: () async => _lookup(),
      classifier: const ThreadContentClassifier(),
      comicIngestService: comicIngest,
      novelIngestService: novelIngest,
    );

    await service.sync();

    // No module ingestion should happen since the only thread is forum-type.
    expect(comicIngest.lightUpsertedTids, isEmpty);
    expect(novelIngest.lightUpsertedTids, isEmpty);
    expect(comicIngest.upsertedTids, isEmpty);
    expect(novelIngest.upsertedTids, isEmpty);
  });
}

// ----- Helpers (shared with favorite_sync_service_test.dart patterns) -----

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
  Future<int> countActiveThreads() async =>
      records.values.where((record) => record.isActive).length;

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
  Future<Set<String>> getActiveTids() async =>
      records.values.where((r) => r.isActive).map((r) => r.tid).toSet();

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async =>
      records.values.where((r) => r.isActive).toList(growable: false);

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async =>
      records[tid];

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async =>
      records.values
          .where((r) => r.isActive && r.detailLoadedAt == null && !excludedTids.contains(r.tid))
          .take(limit)
          .toList(growable: false);

  @override
  Future<List<FavoriteThreadCacheRecord>> getClassifiedModuleRecords() async =>
      records.values
          .where((r) =>
              r.isActive &&
              r.detailLoadedAt != null &&
              r.workId == null &&
              (r.contentKind == ThreadContentKind.comic || r.contentKind == ThreadContentKind.novel))
          .toList(growable: false);

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async => null;

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => _snapshot;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async =>
      const <LibraryWorkItem>[];

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async =>
      const <LibraryCategory>[];

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
      Set<String> activeRemoteTids) async {
    final removed = records.values
        .where((r) => r.isActive && !activeRemoteTids.contains(r.tid))
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
  Future<void> moveThreadToCategory(
      {required String tid, required String toCategoryId}) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => null;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async =>
      const <String, List<LibraryWorkItem>>{};

  @override
  Future<void> renameCategory(
      {required String categoryId, required String newName}) async {}

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
  Future<void> updateThreadWorkId(
      {required String tid, required String? workId}) async {
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
  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  }) async {
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
}) =>
    FavoriteThreadsPage(page: page, perPage: items.length, totalCount: totalCount, items: items);

FavoriteThread _favoriteThread({required String tid, required String title}) =>
    FavoriteThread(
      favid: 'fav-$tid',
      tid: tid,
      title: title,
      description: '',
      author: '作者',
      replies: 0,
      url: 'thread-$tid-1-1.html',
      dateline: 1767225600,
    );

FavoriteThreadCacheRecord _cacheRecord({
  required String tid,
  required String title,
  required ThreadContentKind contentKind,
  String? workId,
  DateTime? detailLoadedAt,
  DateTime? removedAt,
}) =>
    FavoriteThreadCacheRecord(
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

ThreadDetailData _detailForTid(String tid) {
  final fid = switch (tid) {
    '100' => '30',
    '200' => '49',
    '300' => '1',  // Forum (not comic/novel)
    _ => '30',
  };
  final typeid = switch (tid) {
    '100' => '398',
    '200' => '293',
    '300' => '',
    _ => '398',
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

ForumTagLookup _lookup() => ForumTagLookup(
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
