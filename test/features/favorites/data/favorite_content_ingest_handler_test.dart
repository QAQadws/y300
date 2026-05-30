import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/favorites/data/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/favorite_detail_context.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  group('ComicFavoriteContentIngestHandler', () {
    test('declares comic auto refresh and duplicate merge tasks by default', () async {
      final ingestService = _FakeComicIngestService();
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: ingestService,
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
          tagName: '韩国漫画',
        ),
      );

      expect(ingestService.upsertedTids, <String>['100']);
      expect(result.kind, ThreadContentKind.comic);
      expect(result.workId, 'yamibo:100');

      final autoRefresh = result.postTasks.whereType<ComicAutoRefreshTask>().single;
      expect(autoRefresh.comicId, 'yamibo:100');
      expect(autoRefresh.detail.tid, '100');
      expect(autoRefresh.favoriteTitle, '收藏100');
      expect(autoRefresh.sourceTagName, '韩国漫画');
      expect(autoRefresh.forceSearchOnCatalogMiss, isFalse);

      final mergeTasks =
          result.postTasks.whereType<ComicDuplicateMergeTask>().toList();
      expect(mergeTasks, hasLength(1));
      expect(mergeTasks.single.comicId, 'yamibo:100');
    });

    test('omits duplicate merge task when option disabled', () async {
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: _FakeComicIngestService(),
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
          options: const FavoriteIngestOptions(mergeIngestedComic: false),
        ),
      );

      expect(
        result.postTasks.whereType<ComicDuplicateMergeTask>(),
        isEmpty,
      );
      expect(
        result.postTasks.whereType<ComicAutoRefreshTask>(),
        hasLength(1),
      );
    });

    test('forwards forceSearchOnCatalogMiss into auto refresh task', () async {
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: _FakeComicIngestService(),
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
          options: const FavoriteIngestOptions(
            forceComicSearchOnCatalogMiss: true,
          ),
        ),
      );

      final task = result.postTasks.whereType<ComicAutoRefreshTask>().single;
      expect(task.forceSearchOnCatalogMiss, isTrue);
    });

    test('removeFromShelf delegates to ingest service', () async {
      final ingestService = _FakeComicIngestService();
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: ingestService,
      );

      await handler.removeFromShelf(workId: 'yamibo:100');

      expect(ingestService.removedWorkIds, <String>['yamibo:100']);
    });
  });

  group('NovelFavoriteContentIngestHandler', () {
    test('declares shelf refresh task after novel ingest', () async {
      final ingestService = _FakeNovelIngestService();
      final handler = NovelFavoriteContentIngestHandler(
        ingestService: ingestService,
      );

      final result = await handler.ingest(
        _request(
          tid: '200',
          fid: '49',
          typeid: '293',
          kind: ThreadContentKind.novel,
          tagName: '原创',
        ),
      );

      expect(ingestService.upsertedTids, <String>['200']);
      expect(result.kind, ThreadContentKind.novel);
      expect(result.workId, 'novel:49:200');

      final task = result.postTasks.whereType<ShelfRefreshTask>().single;
      expect(task.modules, <LibraryModuleKey>{
        LibraryModuleKey.novel,
        LibraryModuleKey.favorite,
      });
      expect(task.reason, 'favorite_novel_refresh_completed');
      expect(task.source, LibraryMutationSource.novelRefresh);
      expect(task.workId, 'novel:49:200');
      expect(task.tid, '200');
    });
  });

  group('ForumFavoriteContentIngestHandler', () {
    test('returns thread work id without post tasks and removeFromShelf is a no-op', () async {
      const handler = ForumFavoriteContentIngestHandler();

      final result = await handler.ingest(
        _request(
          tid: '300',
          fid: '1',
          kind: ThreadContentKind.forum,
        ),
      );
      await handler.removeFromShelf(workId: 'thread:300');

      expect(result.kind, ThreadContentKind.forum);
      expect(result.workId, 'thread:300');
      expect(result.postTasks, isEmpty);
    });
  });
}

FavoriteContentIngestRequest _request({
  required String tid,
  required String fid,
  required ThreadContentKind kind,
  String typeid = '',
  String? tagName,
  FavoriteIngestOptions options = const FavoriteIngestOptions(),
}) {
  return FavoriteContentIngestRequest(
    context: FavoriteDetailContext(
      record: FavoriteThreadCacheRecord(
        tid: tid,
        favid: 'fav-$tid',
        title: '收藏$tid',
        replies: 0,
        sourceTagName: tagName,
        contentKind: kind,
        firstSeenAt: DateTime(2026, 1, 1),
        lastSeenAt: DateTime(2026, 1, 1),
      ),
      detail: ThreadDetailData(
        tid: tid,
        fid: fid,
        typeid: typeid,
        subject: '主题$tid',
        author: '作者',
        replies: 0,
        views: 1,
        currentPage: 1,
        perPage: 20,
        posts: const <ThreadPost>[],
      ),
      tagName: tagName,
      kind: kind,
    ),
    options: options,
  );
}

class _FakeComicIngestService implements ComicFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    upsertedTids.add(detail.tid);
    return 'yamibo:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _FakeNovelIngestService implements NovelFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    upsertedTids.add(detail.tid);
    return 'novel:${detail.fid}:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}
