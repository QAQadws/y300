import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

class ComicFavoriteContentIngestHandler
    implements FavoriteContentIngestHandler {
  const ComicFavoriteContentIngestHandler({
    required ComicFavoriteIngestService ingestService,
    ComicFavoriteAutoRefreshCoordinator? comicAutoRefreshCoordinator,
    ComicDuplicateMergeService? comicDuplicateMergeService,
    LibraryShelfRefreshBus? shelfRefreshBus,
  })  : _ingestService = ingestService,
        _comicAutoRefreshCoordinator = comicAutoRefreshCoordinator,
        _comicDuplicateMergeService = comicDuplicateMergeService,
        _shelfRefreshBus = shelfRefreshBus;

  final ComicFavoriteIngestService _ingestService;
  final ComicFavoriteAutoRefreshCoordinator? _comicAutoRefreshCoordinator;
  final ComicDuplicateMergeService? _comicDuplicateMergeService;
  final LibraryShelfRefreshBus? _shelfRefreshBus;

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
    );
    await _runComicAutoRefresh(
      comicId: workId,
      request: request,
    );
    final resolvedWorkId = request.options.mergeIngestedComic
        ? await _mergeIngestedComicIfNeeded(workId)
        : workId;
    return FavoriteContentIngestResult(
      kind: kind,
      workId: resolvedWorkId,
    );
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _ingestService.removeFromShelf(workId: workId);
  }

  Future<void> _runComicAutoRefresh({
    required String comicId,
    required FavoriteContentIngestRequest request,
  }) async {
    final coordinator = _comicAutoRefreshCoordinator;
    if (coordinator == null) {
      return;
    }
    try {
      await coordinator.refreshAfterFavoriteIngest(
        comicId: comicId,
        detail: request.context.detail,
        favoriteTitle: request.context.record.title,
        sourceTagName: request.context.tagName,
        forceSearchOnCatalogMiss: request.options.forceComicSearchOnCatalogMiss,
      );
    } catch (_) {
      // 收藏详情已经入库；catalog 引导/队列入队失败不应让本条收藏反复
      // 停留在 detail_loaded_at 为空的状态。后续手动刷新或搜索队列可继续补偿。
    }
  }

  Future<String> _mergeIngestedComicIfNeeded(String comicId) async {
    final service = _comicDuplicateMergeService;
    if (service == null) {
      return comicId;
    }
    try {
      final result = await service.mergeComic(comicId: comicId);
      if (result.changed) {
        _shelfRefreshBus?.notify(
          modules: const <LibraryModuleKey>{
            LibraryModuleKey.comic,
            LibraryModuleKey.favorite,
          },
          reason: 'favorite_comic_duplicate_merge_completed',
        );
      }
      return result.targetComicId.trim().isEmpty
          ? comicId
          : result.targetComicId;
    } catch (_) {
      // 合并是收藏入库后的维护步骤；失败不应让本条收藏回到“未补详情”
      // 状态，后续手动“合并重复”或下一次增量仍可补偿。
      return comicId;
    }
  }
}

class NovelFavoriteContentIngestHandler
    implements FavoriteContentIngestHandler {
  const NovelFavoriteContentIngestHandler({
    required NovelFavoriteIngestService ingestService,
    LibraryShelfRefreshBus? shelfRefreshBus,
  })  : _ingestService = ingestService,
        _shelfRefreshBus = shelfRefreshBus;

  final NovelFavoriteIngestService _ingestService;
  final LibraryShelfRefreshBus? _shelfRefreshBus;

  @override
  ThreadContentKind get kind => ThreadContentKind.novel;

  @override
  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  ) async {
    final workId = await _ingestService.upsertFromThreadDetail(
      detail: request.context.detail,
      sourceTagName: request.context.tagName,
    );
    _shelfRefreshBus?.notify(
      modules: const <LibraryModuleKey>{
        LibraryModuleKey.novel,
        LibraryModuleKey.favorite,
      },
      reason: 'favorite_novel_refresh_completed',
    );
    return FavoriteContentIngestResult(
      kind: kind,
      workId: workId,
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
  })  : _comicHandler = comicHandler,
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
