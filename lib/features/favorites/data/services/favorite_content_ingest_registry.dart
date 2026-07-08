import 'package:y300/features/comic/data/services/comic_favorite_ingest_service.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/services/novel_favorite_ingest_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

class ComicFavoriteContentIngestHandler
    implements FavoriteContentIngestHandler {
  const ComicFavoriteContentIngestHandler({
    required ComicFavoriteIngestService ingestService,
  }) : _ingestService = ingestService;

  final ComicFavoriteIngestService _ingestService;

  @override
  ThreadContentKind get kind => ThreadContentKind.comic;

  @override
  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  ) async {
    final context = request.context;
    final workId = await _ingestService.upsertFromThreadDetail(
      detail: context.detail,
      sourceTagName: context.tagName,
      executionContext: request.options.executionContext,
    );
    // 阶段 3：handler 只声明后处理任务，实际执行交给 LibraryPostIngestTaskRunner。
    // 这样 handler 不再耦合 catalog/搜索队列、重复合并 SQL 与刷新事件总线。
    final tasks = <LibraryPostIngestTask>[
      ComicAutoRefreshTask(
        comicId: workId,
        detail: context.detail,
        favoriteTitle: context.record.title,
        sourceFid: context.detail.fid,
        sourceTypeId: context.detail.typeid,
        sourceTagName: context.tagName,
        forceSearchOnCatalogMiss: request.options.forceComicSearchOnCatalogMiss,
      ),
      if (request.options.mergeIngestedComic)
        ComicDuplicateMergeTask(comicId: workId),
    ];
    return FavoriteContentIngestResult(
      kind: kind,
      workId: workId,
      postTasks: tasks,
    );
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _ingestService.removeFromShelf(workId: workId);
  }
}

class NovelFavoriteContentIngestHandler
    implements FavoriteContentIngestHandler {
  const NovelFavoriteContentIngestHandler({
    required NovelFavoriteIngestService ingestService,
  }) : _ingestService = ingestService;

  final NovelFavoriteIngestService _ingestService;

  @override
  ThreadContentKind get kind => ThreadContentKind.novel;

  @override
  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  ) async {
    final context = request.context;
    final workId = await _ingestService.upsertFromThreadDetail(
      detail: context.detail,
      sourceTagName: context.tagName,
      executionContext: request.options.executionContext,
    );
    return FavoriteContentIngestResult(
      kind: kind,
      workId: workId,
      postTasks: <LibraryPostIngestTask>[
        ShelfRefreshTask(
          modules: <LibraryModuleKey>{
            LibraryModuleKey.novel,
            LibraryModuleKey.favorite,
          },
          reason: 'favorite_novel_refresh_completed',
          source: LibraryMutationSource.novelRefresh,
          workId: workId,
          tid: context.detail.tid,
        ),
      ],
    );
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _ingestService.removeFromShelf(workId: workId);
  }
}

class ForumFavoriteContentIngestHandler
    implements FavoriteContentIngestHandler {
  const ForumFavoriteContentIngestHandler();

  @override
  ThreadContentKind get kind => ThreadContentKind.forum;

  @override
  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  ) async {
    return FavoriteContentIngestResult(
      kind: ThreadContentKind.forum,
      workId: 'thread:${request.context.detail.tid}',
    );
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {}
}

class DefaultFavoriteContentIngestRegistry
    implements FavoriteContentIngestRegistry {
  const DefaultFavoriteContentIngestRegistry({
    required FavoriteContentIngestHandler comicHandler,
    required FavoriteContentIngestHandler novelHandler,
    required FavoriteContentIngestHandler forumHandler,
  }) : _comicHandler = comicHandler,
       _novelHandler = novelHandler,
       _forumHandler = forumHandler;

  final FavoriteContentIngestHandler _comicHandler;
  final FavoriteContentIngestHandler _novelHandler;
  final FavoriteContentIngestHandler _forumHandler;

  @override
  FavoriteContentIngestHandler handlerFor(ThreadContentKind kind) {
    switch (kind) {
      case ThreadContentKind.comic:
        return _comicHandler;
      case ThreadContentKind.novel:
        return _novelHandler;
      case ThreadContentKind.unknown:
      case ThreadContentKind.forum:
        return _forumHandler;
    }
  }
}
