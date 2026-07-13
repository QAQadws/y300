import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/services/novel_download_service.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_recovery_service.dart';

/// 小说详情适配器（Phase 6）。
class NovelDetailAdapter implements DetailModuleAdapter {
  NovelDetailAdapter(
    this._repository, {
    NovelDownloadService? downloadService,
    ImageCacheService? imageCacheService,
    ReadingStateBatchWriter? readingStateBatchWriter,
    required LibraryStateRepository stateRepository,
    NovelSourceStateRepository? sourceStateRepository,
    NovelChapterSyncService Function()? chapterSyncServiceFactory,
    NovelSourceMetadataRecoveryService Function()?
    sourceMetadataRecoveryServiceFactory,
  }) : _downloadService = downloadService,
       _coverCacheService = LibraryCoverCacheService(imageCacheService),
       _readingStateBatchWriter = readingStateBatchWriter,
       _stateRepository = stateRepository,
       _sourceStateRepository = sourceStateRepository,
       _chapterSyncServiceFactory = chapterSyncServiceFactory,
       _sourceMetadataRecoveryServiceFactory =
           sourceMetadataRecoveryServiceFactory;

  final NovelRepository _repository;
  final NovelDownloadService? _downloadService;
  final LibraryCoverCacheService _coverCacheService;
  final ReadingStateBatchWriter? _readingStateBatchWriter;
  final LibraryStateRepository _stateRepository;
  final NovelSourceStateRepository? _sourceStateRepository;
  final NovelChapterSyncService Function()? _chapterSyncServiceFactory;
  final NovelSourceMetadataRecoveryService Function()?
  _sourceMetadataRecoveryServiceFactory;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    final detail = await _repository.getDetail(novelId: workId);
    if (detail == null) {
      throw StateError('小说不存在或已删除');
    }
    final workState = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.novel,
      workId: workId,
    );
    final sourceState = await _sourceStateRepository?.getSourceState(
      novelId: workId,
    );
    final coverImageUrl = detail.coverImageUrl;
    var coverLocalPath = detail.coverLocalPath;
    if ((coverLocalPath == null || coverLocalPath.trim().isEmpty) &&
        coverImageUrl != null &&
        coverImageUrl.trim().isNotEmpty) {
      final cachedCover = await _coverCacheService.ensureProtectedCover(
        cacheKey: ImageCacheKeys.novelCover(workId),
        sourceUrl: coverImageUrl,
        ownerType: ImageCacheOwnerType.novel,
        ownerId: workId,
        role: ImageCacheRole.cover,
      );
      final localPath = cachedCover?.localPath?.trim();
      if (localPath != null && localPath.isNotEmpty) {
        coverLocalPath = localPath;
        if (_repository is NovelCoverCacheWriter) {
          await (_repository as NovelCoverCacheWriter).updateCoverCache(
            novelId: workId,
            coverImageUrl: coverImageUrl,
            coverLocalPath: coverLocalPath,
          );
        }
      }
    }
    return LibraryDetailHeader(
      workId: detail.novelId,
      title: detail.title,
      coverImageUrl: coverImageUrl,
      coverLocalPath: coverLocalPath,
      customCoverLocalPath: detail.customCoverLocalPath,
      author: detail.author,
      sourceTitle: detail.sourceTitle,
      sourceAuthor: detail.sourceAuthor,
      sourceAuthorId: sourceState?.publisherId,
      sourceTid: detail.sourceTid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      inShelf: true,
      intro: workState?.introText ?? sourceState?.sourceIntro,
    );
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    final progress = await _repository.getReadingProgress(novelId: workId);

    final mapped = <LibraryChapterItem>[];
    for (final item in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: item.episodeId,
      );
      final isRead = state?.isRead ?? false;
      mapped.add(
        LibraryChapterItem(
          episodeId: item.episodeId,
          workId: item.novelId,
          title: item.episodeTitle,
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          sourcePid: item.sourcePid,
          publishTimeText: item.datelineText,
          isRead: isRead,
          isDownloaded: state?.isDownloaded ?? false,
          isBookmarked: state?.isBookmarked ?? false,
          progressInfo: _progressInfoForEpisode(
            episodeId: item.episodeId,
            progress: progress,
            isRead: isRead,
          ),
        ),
      );
    }

    final filtered = _applyFilters(mapped, filters);
    return _sortChapters(filtered, sortOption);
  }

  LibraryChapterProgressInfo? _progressInfoForEpisode({
    required String episodeId,
    required NovelReadingProgress? progress,
    required bool isRead,
  }) {
    if (isRead || progress == null || progress.episodeId != episodeId) {
      return null;
    }

    final fraction = progress.progressPercent.clamp(0.0, 1.0).toDouble();
    if (progress.flowMode != NovelReaderFlowMode.vertical) {
      final pageNumber = (progress.pageIndex < 0 ? 0 : progress.pageIndex) + 1;
      return LibraryChapterProgressInfo(
        label: '第 $pageNumber 页',
        isCurrent: true,
        fraction: fraction,
        semanticLabel: fraction > 0
            ? '当前读到第 $pageNumber 页，已读 ${(fraction * 100).round()}%'
            : '当前读到第 $pageNumber 页',
      );
    }

    if (fraction > 0) {
      final percent = (fraction * 100).round().clamp(1, 100);
      return LibraryChapterProgressInfo(
        label: '已读 $percent%',
        isCurrent: true,
        fraction: fraction,
        semanticLabel: '当前章节已读 $percent%',
      );
    }

    if (progress.scrollOffset > 0) {
      return const LibraryChapterProgressInfo(
        label: '阅读中',
        isCurrent: true,
        fraction: 0,
        semanticLabel: '当前章节阅读中',
      );
    }

    return null;
  }

  @override
  Future<void> clearAllReadState({required String workId}) async {
    final writer = _readingStateBatchWriter;
    if (writer != null) {
      await writer.setWorkRead(
        module: LibraryModuleKey.novel,
        workId: workId,
        isRead: false,
      );
      return;
    }
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    for (final episode in episodes) {
      await _stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: episode.episodeId,
        workId: workId,
        isRead: false,
        readAt: null,
      );
    }
  }

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {
    await _downloadService?.deleteChapterDownload(
      novelId: workId,
      episodeId: episodeId,
    );
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: episodeId,
      workId: workId,
      isDownloaded: false,
      downloadedAt: null,
    );
  }

  @override
  Future<void> downloadAll({required String workId}) async {
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    for (final episode in episodes) {
      await markChapterDownloaded(
        workId: workId,
        episodeId: episode.episodeId,
        isDownloaded: true,
      );
    }
  }

  @override
  Future<void> downloadUnread({required String workId}) async {
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    for (final episode in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: episode.episodeId,
      );
      if (!(state?.isRead ?? false)) {
        await markChapterDownloaded(
          workId: workId,
          episodeId: episode.episodeId,
          isDownloaded: true,
        );
      }
    }
  }

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    final progress = await _repository.getReadingProgress(novelId: workId);
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: false,
    );
    if (episodes.isEmpty) {
      return null;
    }
    if (preferContinue &&
        progress != null &&
        episodes.any((episode) => episode.episodeId == progress.episodeId)) {
      return ReaderRouteTarget(workId: workId, episodeId: progress.episodeId);
    }
    return ReaderRouteTarget(
      workId: workId,
      episodeId: episodes.first.episodeId,
    );
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({
    required String workId,
  }) async {
    final detail = await _repository.getDetail(novelId: workId);
    if (detail == null) {
      return null;
    }
    return ThreadRouteTarget(tid: detail.sourceTid, subject: detail.title);
  }

  @override
  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: episodeId,
      workId: workId,
      isBookmarked: isBookmarked,
    );
  }

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) async {
    if (isDownloaded) {
      await _downloadService?.downloadChapter(
        novelId: workId,
        episodeId: episodeId,
      );
    }
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: episodeId,
      workId: workId,
      isDownloaded: isDownloaded,
      downloadedAt: isDownloaded ? DateTime.now() : null,
    );
  }

  @override
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  }) async {
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead,
      readAt: isRead ? DateTime.now() : null,
    );
  }

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) async {
    final sourceRepository = _sourceStateRepository;
    final syncServiceFactory = _chapterSyncServiceFactory;
    if (sourceRepository == null || syncServiceFactory == null) {
      throw StateError('小说章节同步服务尚未配置。');
    }

    var sourceState = await sourceRepository.getSourceState(novelId: workId);
    if (sourceState == null) {
      throw StateError('缺少小说来源信息，无法更新章节。');
    }
    var publisherId = sourceState.publisherId?.trim() ?? '';
    if (publisherId.isEmpty) {
      final recoveryServiceFactory = _sourceMetadataRecoveryServiceFactory;
      if (recoveryServiceFactory == null) {
        throw StateError('来源帖子缺少发布者 ID，无法更新章节。');
      }
      await recoveryServiceFactory().recover(workId);
      sourceState = await sourceRepository.getSourceState(novelId: workId);
      publisherId = sourceState?.publisherId?.trim() ?? '';
    }
    if (sourceState == null || publisherId.isEmpty) {
      throw StateError('来源帖子缺少有效的发布者 ID。');
    }

    final detail = await _repository.getDetail(novelId: workId);
    final tid = detail?.sourceTid.trim() ?? '';
    if (tid.isEmpty) {
      throw StateError('小说缺少来源帖子 ID。');
    }

    final isIncremental =
        sourceState.hydrationState == NovelChapterHydrationState.ready;
    final checkpoint = isIncremental ? sourceState.checkpoint : null;
    if (isIncremental && checkpoint == null) {
      throw StateError('小说章节同步检查点缺失，无法安全执行增量更新。');
    }
    final result = await syncServiceFactory().synchronize(
      NovelChapterSyncRequest(
        novelId: workId,
        tid: tid,
        publisherId: publisherId,
        mode: isIncremental
            ? NovelChapterSyncMode.incremental
            : NovelChapterSyncMode.initialFull,
        checkpoint: checkpoint,
      ),
    );
    return DetailRefreshResult(
      status: DetailRefreshStatus.immediate,
      message: _refreshResultMessage(result),
    );
  }

  String _refreshResultMessage(NovelChapterSyncResult result) {
    if (result.insertedCount == 0 && result.updatedCount == 0) {
      return '已是最新章节';
    }
    return '已新增 ${result.insertedCount} 章，更新 ${result.updatedCount} 章';
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {
    await _stateRepository.upsertWorkState(
      moduleKey: LibraryModuleKey.novel,
      workId: workId,
      introText: intro,
    );
  }

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  }) async {
    final fromCategoryId = await _findCurrentCategoryId(workId);
    if (fromCategoryId == null || fromCategoryId == toCategoryId) {
      return;
    }
    await _repository.moveNovelToCategory(
      novelId: workId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    final categories = await _repository.getCategories();
    return categories
        .map(
          (item) => LibraryCategory(
            categoryId: item.categoryId,
            name: item.name,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt,
          ),
        )
        .toList(growable: false);
  }

  Future<String?> _findCurrentCategoryId(String workId) async {
    final categories = await _repository.getCategories();
    for (final category in categories) {
      final works = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      if (works.any((item) => item.novelId == workId)) {
        return category.categoryId;
      }
    }
    return null;
  }

  List<LibraryChapterItem> _applyFilters(
    List<LibraryChapterItem> source,
    LibraryFilterSet filters,
  ) {
    return source
        .where((chapter) {
          if (!_matchTriState(filters.downloaded, chapter.isDownloaded)) {
            return false;
          }
          if (!_matchTriState(filters.unread, !chapter.isRead)) {
            return false;
          }
          if (!_matchTriState(filters.bookmarked, chapter.isBookmarked)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  List<LibraryChapterItem> _sortChapters(
    List<LibraryChapterItem> source,
    LibraryChapterSortOption sortOption,
  ) {
    final list = [...source];
    int compare(LibraryChapterItem a, LibraryChapterItem b) {
      final result = switch (sortOption.field) {
        LibraryChapterSortField.chapterIndex => a.orderIndex.compareTo(
          b.orderIndex,
        ),
        LibraryChapterSortField.date => (a.publishTimeText ?? '').compareTo(
          b.publishTimeText ?? '',
        ),
        LibraryChapterSortField.name => a.title.compareTo(b.title),
        LibraryChapterSortField.tid => _compareNumericText(
          a.sourcePid ?? '',
          b.sourcePid ?? '',
        ),
      };
      return sortOption.direction == LibrarySortDirection.asc
          ? result
          : -result;
    }

    list.sort(compare);
    return list;
  }

  bool _matchTriState(TriStateFilterValue filterValue, bool flag) {
    return switch (filterValue) {
      TriStateFilterValue.ignore => true,
      TriStateFilterValue.include => flag,
      TriStateFilterValue.exclude => !flag,
    };
  }

  int _compareNumericText(String a, String b) {
    final aNumber = int.tryParse(a);
    final bNumber = int.tryParse(b);
    if (aNumber != null && bNumber != null) {
      return aNumber.compareTo(bNumber);
    }
    return a.compareTo(b);
  }
}
