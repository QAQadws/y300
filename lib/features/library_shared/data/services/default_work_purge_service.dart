import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef ComicWorkPurger = Future<void> Function({required String comicId});
typedef NovelWorkPurger = Future<void> Function({required String novelId});
typedef LibraryWorkStatePurger = Future<void> Function({
  required LibraryModuleKey moduleKey,
  required String workId,
});
typedef FavoriteWorkMarker = Future<int> Function(String workId);
typedef CacheOwnerDeleter = Future<int> Function({
  required ImageCacheOwnerType ownerType,
  required String ownerId,
});
typedef ComicDownloadDeleter = Future<bool> Function({required String workId});
typedef NovelDownloadDeleter = Future<bool> Function({required String novelId});
typedef ComicQueueDeleter = Future<void> Function(String comicId);

class DefaultWorkPurgeService implements WorkPurgeService {
  DefaultWorkPurgeService({
    required ComicWorkPurger purgeComicWork,
    required NovelWorkPurger purgeNovelWork,
    required LibraryWorkStatePurger purgeLibraryWorkState,
    required FavoriteWorkMarker markFavoriteRemovedByWorkId,
    required CacheOwnerDeleter deleteCacheByOwner,
    required ComicDownloadDeleter deleteComicDownloads,
    required NovelDownloadDeleter deleteNovelDownloads,
    required ComicQueueDeleter deleteComicQueueByComicId,
  })  : _purgeLibraryWorkState = purgeLibraryWorkState,
        _markFavoriteRemovedByWorkId = markFavoriteRemovedByWorkId,
        _deleteCacheByOwner = deleteCacheByOwner,
        _strategies = <ThreadContentKind, _WorkPurgeStrategy>{
          ThreadContentKind.comic: _ComicWorkPurgeStrategy(
            purgeComicWork: purgeComicWork,
            deleteComicDownloads: deleteComicDownloads,
            deleteComicQueueByComicId: deleteComicQueueByComicId,
          ),
          ThreadContentKind.novel: _NovelWorkPurgeStrategy(
            purgeNovelWork: purgeNovelWork,
            deleteNovelDownloads: deleteNovelDownloads,
          ),
        };

  final LibraryWorkStatePurger _purgeLibraryWorkState;
  final FavoriteWorkMarker _markFavoriteRemovedByWorkId;
  final CacheOwnerDeleter _deleteCacheByOwner;
  final Map<ThreadContentKind, _WorkPurgeStrategy> _strategies;

  @override
  Future<WorkPurgeResult> purge({
    required String workId,
    required ThreadContentKind kind,
  }) async {
    final normalizedWorkId = workId.trim();
    if (normalizedWorkId.isEmpty) {
      throw ArgumentError('workId 不能为空');
    }
    final strategy = _strategies[kind];
    if (strategy == null) {
      throw UnsupportedError('Work purge is not supported for kind: $kind');
    }

    await strategy.purgeModuleData(normalizedWorkId);
    await _purgeLibraryWorkState(
      moduleKey: strategy.moduleKey,
      workId: normalizedWorkId,
    );
    await _markFavoriteRemovedByWorkId(normalizedWorkId);
    await strategy.purgeAdditionalCoreData(normalizedWorkId);

    final errors = <String>[];
    var purgedCache = false;
    var purgedDownload = false;

    try {
      final deletedCount = await _deleteCacheByOwner(
        ownerType: strategy.ownerType,
        ownerId: normalizedWorkId,
      );
      purgedCache = deletedCount > 0;
    } catch (error) {
      errors.add('清理缓存失败：$error');
    }

    try {
      purgedDownload = await strategy.deleteDownloads(normalizedWorkId);
    } catch (error) {
      errors.add('清理下载失败：$error');
    }

    return WorkPurgeResult(
      workId: normalizedWorkId,
      kind: kind,
      purgedDownload: purgedDownload,
      purgedCache: purgedCache,
      errors: errors,
    );
  }
}

abstract class _WorkPurgeStrategy {
  ThreadContentKind get kind;
  LibraryModuleKey get moduleKey;
  ImageCacheOwnerType get ownerType;

  Future<void> purgeModuleData(String workId);

  Future<void> purgeAdditionalCoreData(String workId) async {}

  Future<bool> deleteDownloads(String workId);
}

class _ComicWorkPurgeStrategy implements _WorkPurgeStrategy {
  _ComicWorkPurgeStrategy({
    required ComicWorkPurger purgeComicWork,
    required ComicDownloadDeleter deleteComicDownloads,
    required ComicQueueDeleter deleteComicQueueByComicId,
  })  : _purgeComicWork = purgeComicWork,
        _deleteComicDownloads = deleteComicDownloads,
        _deleteComicQueueByComicId = deleteComicQueueByComicId;

  final ComicWorkPurger _purgeComicWork;
  final ComicDownloadDeleter _deleteComicDownloads;
  final ComicQueueDeleter _deleteComicQueueByComicId;

  @override
  ThreadContentKind get kind => ThreadContentKind.comic;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  ImageCacheOwnerType get ownerType => ImageCacheOwnerType.comic;

  @override
  Future<void> purgeModuleData(String workId) {
    return _purgeComicWork(comicId: workId);
  }

  @override
  Future<void> purgeAdditionalCoreData(String workId) {
    return _deleteComicQueueByComicId(workId);
  }

  @override
  Future<bool> deleteDownloads(String workId) {
    return _deleteComicDownloads(workId: workId);
  }
}

class _NovelWorkPurgeStrategy implements _WorkPurgeStrategy {
  _NovelWorkPurgeStrategy({
    required NovelWorkPurger purgeNovelWork,
    required NovelDownloadDeleter deleteNovelDownloads,
  })  : _purgeNovelWork = purgeNovelWork,
        _deleteNovelDownloads = deleteNovelDownloads;

  final NovelWorkPurger _purgeNovelWork;
  final NovelDownloadDeleter _deleteNovelDownloads;

  @override
  ThreadContentKind get kind => ThreadContentKind.novel;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  ImageCacheOwnerType get ownerType => ImageCacheOwnerType.novel;

  @override
  Future<void> purgeModuleData(String workId) {
    return _purgeNovelWork(novelId: workId);
  }

  @override
  Future<void> purgeAdditionalCoreData(String workId) async {}

  @override
  Future<bool> deleteDownloads(String workId) {
    return _deleteNovelDownloads(novelId: workId);
  }
}
