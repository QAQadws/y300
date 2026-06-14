import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/reading_state_batch_writer.dart';

/// 漫画详情适配器（Phase 6）。
///
/// 负责把漫画仓储数据映射到统一详情模型，并接入章节状态筛选/排序。
/// 刷新抓取通过 ComicEpisodeRefreshService 下沉到漫画域 services，
/// 而“合并章节/提升封面/通知书架”则统一交给 ComicRefreshOutcomeApplier，
/// 保证统一详情页只保留编排，不耦合漫画刷新策略细节。
class ComicDetailAdapter implements DetailModuleAdapter, DetailMetadataEditor {
  ComicDetailAdapter(
    this._repository, {
    ComicEpisodeRefreshService? refreshService,
    ComicSearchRefreshQueueEnqueuer? searchQueue,
    ComicFirstEpisodeCoverService? firstEpisodeCoverService,
    ComicRefreshOutcomeApplier? refreshOutcomeApplier,
    ComicDownloadService? downloadService,
    ImageCacheService? imageCacheService,
    ReadingStateBatchWriter? readingStateBatchWriter,
    BulkDownloadUseCase? bulkDownloadUseCase,
    ComicIncrementalEpisodeDiscovery? incrementalDiscovery,
    ComicEpisodeDiscoveryService? discoveryService,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
    ComicTitleAnalyzer titleAnalyzer = const PetitComicTitleAnalyzer(),
    required LibraryStateRepository stateRepository,
  })  : _refreshService = refreshService,
        _searchQueue = searchQueue,
        _firstEpisodeCoverService = firstEpisodeCoverService,
        _refreshOutcomeApplier = refreshOutcomeApplier,
        _downloadService = downloadService,
        _imageCacheService = imageCacheService,
        _readingStateBatchWriter = readingStateBatchWriter,
        _bulkDownloadUseCase = bulkDownloadUseCase,
        _incrementalDiscovery = incrementalDiscovery,
        _discoveryService = discoveryService,
        _featureFlags = featureFlags,
        _titleAnalyzer = titleAnalyzer,
        _stateRepository = stateRepository;

  final ComicRepository _repository;
  final ComicEpisodeRefreshService? _refreshService;
  final ComicSearchRefreshQueueEnqueuer? _searchQueue;
  final ComicFirstEpisodeCoverService? _firstEpisodeCoverService;
  final ComicRefreshOutcomeApplier? _refreshOutcomeApplier;
  final ComicDownloadService? _downloadService;
  final ImageCacheService? _imageCacheService;
  final ReadingStateBatchWriter? _readingStateBatchWriter;
  final BulkDownloadUseCase? _bulkDownloadUseCase;
  final ComicIncrementalEpisodeDiscovery? _incrementalDiscovery;
  final ComicEpisodeDiscoveryService? _discoveryService;
  final ComicReaderFeatureFlags _featureFlags;
  final ComicTitleAnalyzer _titleAnalyzer;
  final LibraryStateRepository _stateRepository;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      throw StateError('漫画不存在或已删除');
    }
    final workState = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
    );
    final customTags = await _stateRepository.getWorkTags(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
    );
    final inShelf = await _repository.isInShelf(comicId: workId);
    final useCustomMetadata = _featureFlags.readerCustomMetadataEnabled;
    final customCoverImageUrl =
        useCustomMetadata ? detail.customCoverImageUrl?.trim() : null;
    // Local repository returns `coverImageUrl` as custom-or-source for normal
    // UI.  The feature flag must be able to suppress that custom layer fully.
    var coverImageUrl = useCustomMetadata
        ? detail.coverImageUrl
        : _sourceCoverImageUrl(detail);
    var coverLocalPath = useCustomMetadata
        ? detail.coverLocalPath
        : _sourceCoverLocalPath(detail);
    var customCoverLocalPath =
        useCustomMetadata ? detail.customCoverLocalPath : null;
    if (coverImageUrl == null || coverImageUrl.trim().isEmpty) {
      final promoted = await _firstEpisodeCoverService?.promoteIfPossible(
        comicId: workId,
      );
      if (promoted == true) {
        final refreshed = await _repository.getComicDetail(comicId: workId);
        if (refreshed != null) {
          coverImageUrl = useCustomMetadata
              ? refreshed.coverImageUrl
              : _sourceCoverImageUrl(refreshed);
          coverLocalPath = useCustomMetadata
              ? refreshed.coverLocalPath
              : _sourceCoverLocalPath(refreshed);
          customCoverLocalPath =
              useCustomMetadata ? refreshed.customCoverLocalPath : null;
        }
      }
      // 漫画初始封面使用“tid 最小的话的第一张图”。orderIndex 只代表
      // 当前解析顺序，遇到目录/补全章节时不一定等于真实首话。
      if (coverImageUrl == null || coverImageUrl.trim().isEmpty) {
        coverImageUrl = await _loadFirstEpisodeImageUrl(workId);
      }
    }
    if (customCoverImageUrl != null &&
        customCoverImageUrl.isNotEmpty &&
        (customCoverLocalPath == null || customCoverLocalPath.trim().isEmpty)) {
      final cachedCustomCover = await _cacheCover(
        comicId: workId,
        sourceUrl: customCoverImageUrl,
        cacheKey: ImageCacheKeys.customCover(
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: workId,
        ),
        role: ImageCacheRole.customCover,
      );
      if (cachedCustomCover?.localPath != null) {
        customCoverLocalPath = cachedCustomCover!.localPath;
        if (_repository is ComicCoverCacheWriter) {
          await (_repository as ComicCoverCacheWriter).updateCoverCache(
            comicId: workId,
            customCoverLocalPath: customCoverLocalPath,
          );
        }
      }
      if (customCoverLocalPath == null || customCoverLocalPath.trim().isEmpty) {
        // 自定义远程封面应优先于普通本地封面；缓存未完成时让 UI 使用远程图。
        coverLocalPath = null;
      }
    } else if ((coverLocalPath == null || coverLocalPath.trim().isEmpty) &&
        coverImageUrl != null &&
        coverImageUrl.trim().isNotEmpty) {
      final cachedCover = await _cacheCover(
        comicId: workId,
        sourceUrl: coverImageUrl,
        cacheKey: ImageCacheKeys.comicCover(workId),
        role: ImageCacheRole.cover,
      );
      if (cachedCover?.localPath != null) {
        coverLocalPath = cachedCover!.localPath;
        if (_repository is ComicCoverCacheWriter) {
          final writer = _repository as ComicCoverCacheWriter;
          await writer.updateCoverCache(
            comicId: workId,
            coverImageUrl: coverImageUrl,
            coverLocalPath: coverLocalPath,
          );
        }
      }
    }
    return LibraryDetailHeader(
      workId: detail.comicId,
      title: useCustomMetadata
          ? detail.title
          : (detail.sourceTitle ?? detail.title),
      coverImageUrl: coverImageUrl,
      customCoverImageUrl: useCustomMetadata ? customCoverImageUrl : null,
      coverLocalPath: coverLocalPath,
      customCoverLocalPath: useCustomMetadata ? customCoverLocalPath : null,
      author: useCustomMetadata
          ? detail.author
          : (detail.sourceAuthor ?? detail.author),
      sourceAuthor: detail.sourceAuthor,
      customAuthor: useCustomMetadata ? detail.customAuthor : null,
      translationGroup: useCustomMetadata
          ? detail.translationGroup
          : (detail.sourceTranslationGroup ?? detail.translationGroup),
      sourceTitle: detail.sourceTitle,
      customTitle: useCustomMetadata ? detail.customTitle : null,
      sourceTranslationGroup: detail.sourceTranslationGroup,
      customTranslationGroup:
          useCustomMetadata ? detail.customTranslationGroup : null,
      customSearchTitle: useCustomMetadata ? detail.customSearchTitle : null,
      sourceTid: detail.sourceTid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      customTags: customTags,
      inShelf: inShelf,
      intro: workState?.introText,
    );
  }

  Future<String?> _loadFirstEpisodeImageUrl(String workId) async {
    final episodes = await _repository.getComicEpisodes(comicId: workId, descending: false);
    if (episodes.isEmpty) {
      return null;
    }
    final ordered = [...episodes]..sort(_compareEpisodesByFirstTid);
    for (final episode in ordered) {
      final images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
      if (images.isNotEmpty) {
        return images.first.imageUrl;
      }
    }
    return null;
  }

  int _compareEpisodesByFirstTid(ComicEpisodeItem a, ComicEpisodeItem b) {
    final aTid = int.tryParse(a.sourceTid.trim());
    final bTid = int.tryParse(b.sourceTid.trim());
    if (aTid != null && bTid != null && aTid != bTid) {
      return aTid.compareTo(bTid);
    }
    if (aTid != null && bTid == null) {
      return -1;
    }
    if (aTid == null && bTid != null) {
      return 1;
    }
    final order = a.orderIndex.compareTo(b.orderIndex);
    if (order != 0) {
      return order;
    }
    return a.episodeId.compareTo(b.episodeId);
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    final episodes = await _repository.getComicEpisodes(
      comicId: workId,
      descending: false,
    );
    final progress = await _repository.getLastReadProgress(comicId: workId);

    final mapped = <LibraryChapterItem>[];
    for (final item in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: item.episodeId,
      );
      final isRead = state?.isRead ?? false;
      mapped.add(
        LibraryChapterItem(
          episodeId: item.episodeId,
          workId: item.comicId,
          title: item.episodeTitle?.trim().isNotEmpty == true ? item.episodeTitle! : '章节 ${item.sourceTid}',
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          publishTimeText: item.publishTimeText,
          isRead: isRead,
          isDownloaded: state?.isDownloaded ?? false,
          isBookmarked: state?.isBookmarked ?? false,
          progressInfo: await _progressInfoForEpisode(
            episode: item,
            progress: progress,
            isRead: isRead,
          ),
        ),
      );
    }

    final filtered = _applyFilters(mapped, filters);
    return _sortChapters(filtered, sortOption);
  }

  Future<LibraryChapterProgressInfo?> _progressInfoForEpisode({
    required ComicEpisodeItem episode,
    required ComicReadingProgress? progress,
    required bool isRead,
  }) async {
    if (isRead || progress == null || progress.episodeId != episode.episodeId) {
      return null;
    }
    final rawImageIndex = progress.imageIndex < 0 ? 0 : progress.imageIndex;
    final images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    if (images.isEmpty) {
      final pageNumber = rawImageIndex + 1;
      return LibraryChapterProgressInfo(
        label: '第 $pageNumber 页',
        isCurrent: true,
        semanticLabel: '当前读到第 $pageNumber 页',
      );
    }

    final clampedImageIndex = rawImageIndex.clamp(0, images.length - 1).toInt();
    final pageNumber = clampedImageIndex + 1;
    return LibraryChapterProgressInfo(
      label: '第 $pageNumber 页',
      isCurrent: true,
      fraction: pageNumber / images.length,
      semanticLabel: '当前读到第 $pageNumber 页，共 ${images.length} 页',
    );
  }

  @override
  Future<void> clearAllReadState({required String workId}) async {
    final writer = _readingStateBatchWriter;
    if (writer != null) {
      await writer.setWorkRead(
        module: LibraryModuleKey.comic,
        workId: workId,
        isRead: false,
      );
      return;
    }
    final episodes = await _repository.getComicEpisodes(comicId: workId, descending: false);
    for (final episode in episodes) {
      await _stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
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
    await _downloadService?.deleteEpisodeDownload(
      comicId: workId,
      episodeId: episodeId,
    );
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: workId,
      isDownloaded: false,
      downloadedAt: null,
    );
  }

  @override
  Future<void> downloadAll({required String workId}) async {
    final bulkDownloadUseCase = _bulkDownloadUseCase;
    if (bulkDownloadUseCase != null) {
      await bulkDownloadUseCase.downloadComics(<String>{workId});
      return;
    }
    final episodes = await _repository.getComicEpisodes(comicId: workId, descending: false);
    for (final episode in episodes) {
      await markChapterDownloaded(workId: workId, episodeId: episode.episodeId, isDownloaded: true);
    }
  }

  @override
  Future<void> downloadUnread({required String workId}) async {
    final episodes = await _repository.getComicEpisodes(comicId: workId, descending: false);
    for (final episode in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: episode.episodeId,
      );
      if (!(state?.isRead ?? false)) {
        await markChapterDownloaded(workId: workId, episodeId: episode.episodeId, isDownloaded: true);
      }
    }
  }

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    final episodes = await _repository.getComicEpisodes(comicId: workId, descending: false);
    if (episodes.isEmpty) {
      return null;
    }
    final targetEpisodeId = preferContinue
        ? await _resolveContinueEpisodeId(
            workId: workId,
            episodes: episodes,
          )
        : episodes.first.episodeId;
    return ReaderRouteTarget(workId: workId, episodeId: targetEpisodeId);
  }

  String? _sourceCoverImageUrl(ComicDetail detail) {
    final custom = detail.customCoverImageUrl?.trim();
    final cover = detail.coverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty && cover == custom) {
      return null;
    }
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _sourceCoverLocalPath(ComicDetail detail) {
    final custom = detail.customCoverLocalPath?.trim();
    final cover = detail.coverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty && cover == custom) {
      return null;
    }
    return cover == null || cover.isEmpty ? null : cover;
  }

  Future<String> _resolveContinueEpisodeId({
    required String workId,
    required List<ComicEpisodeItem> episodes,
  }) async {
    final validEpisodeIds = episodes.map((episode) => episode.episodeId).toSet();

    final progress = await _repository.getLastReadProgress(comicId: workId);
    if (progress != null && validEpisodeIds.contains(progress.episodeId)) {
      return progress.episodeId;
    }

    final workState = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
    );
    final stateEpisodeId = workState?.lastReadEpisodeId;
    if (stateEpisodeId != null && validEpisodeIds.contains(stateEpisodeId)) {
      return stateEpisodeId;
    }

    // 没有历史进度时，优先从第一章未读章节开始。无状态章节按未读处理，
    // 与详情列表和书架角标的 Phase 2 语义保持一致。
    for (final episode in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: episode.episodeId,
      );
      if (!(state?.isRead ?? false)) {
        return episode.episodeId;
      }
    }

    return episodes.first.episodeId;
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({required String workId}) async {
    final detail = await _repository.getComicDetail(comicId: workId);
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
      moduleKey: LibraryModuleKey.comic,
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
      await _downloadService?.downloadEpisode(
        comicId: workId,
        episodeId: episodeId,
      );
    }
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
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
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: workId,
      isRead: isRead,
      readAt: isRead ? DateTime.now() : null,
    );
  }

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      return DetailRefreshResult.skipped;
    }
    final refreshService = _refreshService;
    final refreshOutcomeApplier = _refreshOutcomeApplier;
    if (refreshService == null || refreshOutcomeApplier == null) {
      return DetailRefreshResult.skipped;
    }
    final request = _buildRefreshRequest(detail);

    // Step 1: Catalog 快速路径（有持久化 catalogUrl 时跳过帖子详情请求）
    final catalogUrl = detail.catalogUrl;
    if (catalogUrl != null && catalogUrl.isNotEmpty) {
      final direct = await refreshService.fetchCatalogDirect(catalogUrl);
      if (direct.catalogMatched && direct.hasLinks) {
        await _applyRefreshOutcome(
          applier: refreshOutcomeApplier,
          comicId: workId,
          sourceTid: detail.sourceTid,
          links: direct.links,
          source: direct.source,
          reason: 'comic_detail_catalog_direct_refresh',
          catalogUrl: direct.catalogUrl,
        );
        return DetailRefreshResult.immediate;
      }
    }

    // Step 2: 获取当前帖详情（为增量发现提供解析数据）
    final parsedRoot = await _fetchAndParseCurrentThread(detail.sourceTid);

    // Step 2.5: catalogUrl 动态补全
    final discoveredCatalogUrl = parsedRoot?.catalogUrl;
    if (discoveredCatalogUrl != null && discoveredCatalogUrl.isNotEmpty) {
      // 持久化新发现的 catalogUrl，下次刷新可直接走快速路径
      await _repository.updateCatalogUrl(
        comicId: workId,
        catalogUrl: discoveredCatalogUrl,
      );
      // 立即尝试 catalog 快速路径
      final catalogRetry = await refreshService
          .fetchCatalogDirect(discoveredCatalogUrl);
      if (catalogRetry.catalogMatched && catalogRetry.hasLinks) {
        await _applyRefreshOutcome(
          applier: refreshOutcomeApplier,
          comicId: workId,
          sourceTid: detail.sourceTid,
          links: catalogRetry.links,
          source: catalogRetry.source,
          reason: 'comic_detail_catalog_retry_refresh',
          catalogUrl: catalogRetry.catalogUrl,
        );
        return DetailRefreshResult.immediate;
      }
    }

    // Step 3: 入搜索队列（异步，不阻塞后续步骤）
    final searchQueue = _searchQueue;
    int? enqueuedPosition;
    Duration? enqueuedDuration;
    if (searchQueue != null) {
      final queued = await searchQueue.enqueue(
        request: request,
        title: _queueTitle(detail),
        origin: ComicSearchRefreshOrigin.detailManual,
      );
      enqueuedPosition = queued.position;
      enqueuedDuration = queued.estimatedDuration;
    }

    // Step 4: 增量章节发现
    final knownTids = await _getKnownEpisodeTids(workId);
    final incrementalLinks = await _runIncrementalDiscovery(
      parsedRoot: parsedRoot,
      knownTids: knownTids,
    );

    // Step 5: 合并增量结果
    if (incrementalLinks.isNotEmpty) {
      await _applyRefreshOutcome(
        applier: refreshOutcomeApplier,
        comicId: workId,
        sourceTid: detail.sourceTid,
        links: incrementalLinks,
        source: ComicEpisodeRefreshSource.currentOnly,
        reason: 'comic_detail_incremental_refresh',
      );
      return DetailRefreshResult.immediate;
    }

    // 无增量结果：返回队列状态
    if (enqueuedPosition != null) {
      return DetailRefreshResult.queued(
        queuePosition: enqueuedPosition,
        estimatedDuration: enqueuedDuration ?? Duration.zero,
      );
    }
    return const DetailRefreshResult(
      status: DetailRefreshStatus.skipped,
      message: '未提取到新的章节链接',
    );
  }

  Future<ParsedThreadResult?> _fetchAndParseCurrentThread(String tid) async {
    final discoveryService = _discoveryService;
    if (discoveryService == null) return null;
    return discoveryService.fetchAndParseThread(tid);
  }

  Future<Set<String>> _getKnownEpisodeTids(String comicId) async {
    return _repository.getKnownEpisodeTids(comicId: comicId);
  }

  Future<List<ComicEpisodeLink>> _runIncrementalDiscovery({
    required ParsedThreadResult? parsedRoot,
    required Set<String> knownTids,
  }) async {
    final incrementalDiscovery = _incrementalDiscovery;
    if (parsedRoot == null || incrementalDiscovery == null) {
      return const <ComicEpisodeLink>[];
    }

    final episodeLinks = parsedRoot.episodeLinks;
    final recursiveCandidates = parsedRoot.recursiveTidCandidates;

    // 判断模式
    if (episodeLinks.length >= 3 || recursiveCandidates.length > 1) {
      // Direct 模式：多个跳转链接
      return incrementalDiscovery.discoverDirectIncremental(
        currentLinks: episodeLinks,
        knownTids: knownTids,
      );
    } else if (recursiveCandidates.length == 1) {
      // Recursive 模式：单链
      return incrementalDiscovery.discoverRecursiveIncremental(
        startTid: recursiveCandidates.first,
        knownTids: knownTids,
      );
    }

    return const <ComicEpisodeLink>[];
  }

  Future<void> _applyRefreshOutcome({
    required ComicRefreshOutcomeApplier applier,
    required String comicId,
    required String sourceTid,
    required List<ComicEpisodeLink> links,
    required ComicEpisodeRefreshSource source,
    required String reason,
    String? catalogUrl,
  }) async {
    await applier.apply(
      ComicRefreshApplyRequest(
        comicId: comicId,
        sourceTid: sourceTid,
        links: links,
        source: source,
        mutationSource: LibraryMutationSource.comicRefresh,
        reason: reason,
        catalogUrl: catalogUrl,
      ),
    );
  }

  ComicEpisodeRefreshRequest _buildRefreshRequest(ComicDetail detail) {
    return ComicEpisodeRefreshRequest(
      comicId: detail.comicId,
      sourceTid: detail.sourceTid,
      displayTitle: detail.displayTitle,
      sourceTitle: detail.sourceTitle,
      customTitle:
          _featureFlags.readerCustomMetadataEnabled ? detail.customTitle : null,
      customSearchTitle: _featureFlags.readerCustomMetadataEnabled
          ? detail.customSearchTitle
          : null,
      catalogUrl: detail.catalogUrl,
    );
  }

  String _queueTitle(ComicDetail detail) {
    // Custom search title is user-authored, so it stays highest priority and is
    // only trimmed. The display title fallback must be cleaned through the
    // analyzer so the queue/notification no longer leaks the raw thread title.
    final customSearchTitle = _featureFlags.readerCustomMetadataEnabled
        ? detail.customSearchTitle?.trim()
        : null;
    if (customSearchTitle != null && customSearchTitle.isNotEmpty) {
      return customSearchTitle;
    }
    final displayTitle = detail.displayTitle.trim();
    if (displayTitle.isNotEmpty) {
      final cleanBookName = _titleAnalyzer.analyze(displayTitle).cleanBookName.trim();
      if (cleanBookName.isNotEmpty) {
        return cleanBookName;
      }
      return displayTitle;
    }
    return detail.sourceTid;
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {
    await _stateRepository.upsertWorkState(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
      introText: intro,
    );
  }

  @override
  Future<void> updateCustomMetadata({
    required String workId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) {
    return _repository.updateCustomMetadata(
      comicId: workId,
      customTitle: customTitle,
      customAuthor: customAuthor,
      customTranslationGroup: customTranslationGroup,
      customSearchTitle: customSearchTitle,
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
    await _repository.moveComicToCategory(
      comicId: workId,
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

  @override
  Future<List<LibraryTag>> getWorkTags({required String workId}) {
    return _stateRepository.getWorkTags(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
    );
  }

  @override
  Future<List<LibraryTag>> getAllTags() {
    return _stateRepository.getTags();
  }

  @override
  Future<void> addExistingTagToWork({
    required String workId,
    required String tagId,
  }) {
    return _stateRepository.bindTagToWork(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
      tagId: tagId,
    );
  }

  @override
  Future<void> addNewTagToWork({
    required String workId,
    required String tagName,
  }) async {
    final tagId = await _stateRepository.createTag(name: tagName);
    await _stateRepository.bindTagToWork(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
      tagId: tagId,
    );
  }

  @override
  Future<void> removeTagFromWork({
    required String workId,
    required String tagId,
  }) {
    return _stateRepository.unbindTagFromWork(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
      tagId: tagId,
    );
  }

  Future<String?> _findCurrentCategoryId(String workId) async {
    final categories = await _repository.getCategories();
    for (final category in categories) {
      final works = await _repository.getShelfItems(categoryId: category.categoryId);
      if (works.any((item) => item.comicId == workId)) {
        return category.categoryId;
      }
    }
    return null;
  }

  Future<CachedImageResult?> _cacheCover({
    required String comicId,
    required String sourceUrl,
    required String cacheKey,
    required ImageCacheRole role,
  }) async {
    final cacheService = _imageCacheService;
    if (cacheService == null) {
      return null;
    }
    final result = await cacheService.ensureCached(
      ImageCacheRequest(
        cacheKey: cacheKey,
        sourceUrl: sourceUrl,
        ownerType: ImageCacheOwnerType.comic,
        ownerId: comicId,
        role: role,
        protected: true,
      ),
    );
    return result.success ? result : null;
  }

  List<LibraryChapterItem> _applyFilters(
    List<LibraryChapterItem> source,
    LibraryFilterSet filters,
  ) {
    return source.where((chapter) {
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
    }).toList(growable: false);
  }

  List<LibraryChapterItem> _sortChapters(
    List<LibraryChapterItem> source,
    LibraryChapterSortOption sortOption,
  ) {
    final list = [...source];
    int compare(LibraryChapterItem a, LibraryChapterItem b) {
      final result = switch (sortOption.field) {
        LibraryChapterSortField.chapterIndex => a.orderIndex.compareTo(b.orderIndex),
        LibraryChapterSortField.date => (a.publishTimeText ?? '').compareTo(b.publishTimeText ?? ''),
        LibraryChapterSortField.name => a.title.compareTo(b.title),
        LibraryChapterSortField.tid => (a.sourceTid ?? '').compareTo(b.sourceTid ?? ''),
      };
      return sortOption.direction == LibrarySortDirection.asc ? result : -result;
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
}
