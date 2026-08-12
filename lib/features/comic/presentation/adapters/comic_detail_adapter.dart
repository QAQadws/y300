import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_url_policy.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_episode_sequence.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_manual_episode_url_policy.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_operation_failure.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_source_id_comparator.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

/// 漫画详情适配器（Phase 6）。
///
/// 负责把漫画仓储数据映射到统一详情模型，并接入章节状态筛选/排序。
/// 刷新抓取通过 ComicEpisodeRefreshService 下沉到漫画域 services，
/// 而“合并章节/提升封面/通知书架”则统一交给 ComicRefreshOutcomeApplier，
/// 保证统一详情页只保留编排，不耦合漫画刷新策略细节。
class ComicDetailAdapter
    implements
        DetailModuleAdapter,
        DetailChapterReadStateAdapter,
        DetailWorkReadingResetAdapter,
        DetailChapterDownloadAdapter,
        DetailChapterDownloadActivityAdapter,
        DetailMetadataEditor,
        DetailCatalogEditor,
        DetailChapterManagementAdapter,
        DetailCoverEditor {
  ComicDetailAdapter(
    this._repository, {
    ComicEpisodeRefreshService? refreshService,
    ComicSearchRefreshQueueEnqueuer? searchQueue,
    ComicFirstEpisodeCoverService? firstEpisodeCoverService,
    ComicRefreshOutcomeApplier? refreshOutcomeApplier,
    ComicDownloadService? downloadService,
    ComicDownloadQueue? downloadQueue,
    LibraryCoverStore? coverStore,
    BulkDownloadUseCase? bulkDownloadUseCase,
    ComicIncrementalEpisodeDiscovery? incrementalDiscovery,
    ComicEpisodeDiscoveryService? discoveryService,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
    ComicTitleAnalyzer titleAnalyzer = const PetitComicTitleAnalyzer(),
    ComicCatalogUrlPolicy catalogUrlPolicy = const ComicCatalogUrlPolicy(),
    ComicManualEpisodeUrlPolicy manualEpisodeUrlPolicy =
        const ComicManualEpisodeUrlPolicy(),
    required LibraryStateRepository stateRepository,
  }) : _refreshService = refreshService,
       _searchQueue = searchQueue,
       _firstEpisodeCoverService = firstEpisodeCoverService,
       _refreshOutcomeApplier = refreshOutcomeApplier,
       _downloadService = downloadService,
       _downloadQueue = downloadQueue,
       _coverStore = coverStore,
       _bulkDownloadUseCase = bulkDownloadUseCase,
       _incrementalDiscovery = incrementalDiscovery,
       _discoveryService = discoveryService,
       _featureFlags = featureFlags,
       _titleAnalyzer = titleAnalyzer,
       _catalogUrlPolicy = catalogUrlPolicy,
       _manualEpisodeUrlPolicy = manualEpisodeUrlPolicy,
       _stateRepository = stateRepository;

  static const ComicEpisodeSequence _episodeSequence = ComicEpisodeSequence();

  final ComicRepository _repository;
  final ComicEpisodeRefreshService? _refreshService;
  final ComicSearchRefreshQueueEnqueuer? _searchQueue;
  final ComicFirstEpisodeCoverService? _firstEpisodeCoverService;
  final ComicRefreshOutcomeApplier? _refreshOutcomeApplier;
  final ComicDownloadService? _downloadService;
  final ComicDownloadQueue? _downloadQueue;
  final LibraryCoverStore? _coverStore;
  final BulkDownloadUseCase? _bulkDownloadUseCase;
  final ComicIncrementalEpisodeDiscovery? _incrementalDiscovery;
  final ComicEpisodeDiscoveryService? _discoveryService;
  final ComicReaderFeatureFlags _featureFlags;
  final ComicTitleAnalyzer _titleAnalyzer;
  final ComicCatalogUrlPolicy _catalogUrlPolicy;
  final ComicManualEpisodeUrlPolicy _manualEpisodeUrlPolicy;
  final LibraryStateRepository _stateRepository;

  @override
  Listenable? get chapterDownloadActivityListenable => _downloadQueue?.snapshot;

  @override
  bool isChapterDownloadActive({
    required String workId,
    required String episodeId,
  }) {
    final queue = _downloadQueue;
    if (queue == null) {
      return false;
    }
    return queue.snapshot.value.entries.any(
      (entry) =>
          entry.comicId == workId &&
          entry.episodeId == episodeId &&
          entry.isActive,
    );
  }

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  DetailMetadataEditorConfig get metadataEditorConfig =>
      const DetailMetadataEditorConfig();

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.workNotFound,
      );
    }
    final workState = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
    );
    final inShelf = await _repository.isInShelf(comicId: workId);
    final useCustomMetadata = _featureFlags.readerCustomMetadataEnabled;
    final customCoverImageUrl = useCustomMetadata
        ? detail.customCoverImageUrl?.trim()
        : null;
    // Local repository returns `coverImageUrl` as custom-or-source for normal
    // UI.  The feature flag must be able to suppress that custom layer fully.
    var coverImageUrl = useCustomMetadata
        ? detail.coverImageUrl
        : _sourceCoverImageUrl(detail);
    var coverLocalPath = useCustomMetadata
        ? detail.coverLocalPath
        : _sourceCoverLocalPath(detail);
    var customCoverLocalPath = useCustomMetadata
        ? detail.customCoverLocalPath
        : null;
    var coverRevision = detail.coverRevision;
    var customCoverRevision = detail.customCoverRevision;
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
          customCoverLocalPath = useCustomMetadata
              ? refreshed.customCoverLocalPath
              : null;
          coverRevision = refreshed.coverRevision;
          customCoverRevision = refreshed.customCoverRevision;
        }
      }
      // 漫画初始封面使用“tid 最小的话的第一张图”。orderIndex 只代表
      // 当前解析顺序，遇到目录/补全章节时不一定等于真实首话。
      if (coverImageUrl == null || coverImageUrl.trim().isEmpty) {
        coverImageUrl = await _loadFirstEpisodeImageUrl(workId);
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
      customCoverFocusX: useCustomMetadata ? detail.customCoverFocusX : null,
      customCoverFocusY: useCustomMetadata ? detail.customCoverFocusY : null,
      coverAsset: LibraryCoverAssetFactory.preferred(
        ownerType: 'comic',
        ownerId: workId,
        sourceUrl: coverImageUrl,
        sourceLegacyPath: coverLocalPath,
        sourceRevision: coverRevision,
        customSourceUrl: useCustomMetadata ? customCoverImageUrl : null,
        customLegacyPath: useCustomMetadata ? customCoverLocalPath : null,
        customRevision: customCoverRevision,
      ),
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
      customTranslationGroup: useCustomMetadata
          ? detail.customTranslationGroup
          : null,
      customSearchTitle: useCustomMetadata ? detail.customSearchTitle : null,
      sourceTid: detail.sourceTid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      inShelf: inShelf,
      intro: workState?.introText,
    );
  }

  Future<String?> _loadFirstEpisodeImageUrl(String workId) async {
    final episodes = await _repository.getComicEpisodes(
      comicId: workId,
      descending: false,
    );
    if (episodes.isEmpty) {
      return null;
    }
    final ordered = _episodeSequence.order(episodes);
    for (final episode in ordered) {
      final images = await _repository.getEpisodeImages(
        episodeId: episode.episodeId,
      );
      if (images.isNotEmpty) {
        return images.first.imageUrl;
      }
    }
    return null;
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
    final progresses = await _repository.getReadingProgresses(comicId: workId);
    final progressByEpisodeId = <String, ComicReadingProgress>{
      for (final progress in progresses) progress.episodeId: progress,
    };

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
          title: item.episodeTitle?.trim().isNotEmpty == true
              ? item.episodeTitle!
              : '',
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          publishTimeText: item.publishTimeText,
          isRead: isRead,
          isDownloaded: state?.isDownloaded ?? false,
          isBookmarked: state?.isBookmarked ?? false,
          progressInfo: await _progressInfoForEpisode(
            episode: item,
            progress: progressByEpisodeId[item.episodeId],
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
    if (isRead || progress == null) {
      return null;
    }
    final rawImageIndex = progress.imageIndex < 0 ? 0 : progress.imageIndex;
    final images = await _repository.getEpisodeImages(
      episodeId: episode.episodeId,
    );
    if (images.isEmpty) {
      final pageNumber = rawImageIndex + 1;
      return LibraryChapterProgressInfo(
        kind: LibraryChapterProgressKind.currentPage,
        isCurrent: true,
        currentPage: pageNumber,
      );
    }

    final clampedImageIndex = rawImageIndex.clamp(0, images.length - 1).toInt();
    final pageNumber = clampedImageIndex + 1;
    return LibraryChapterProgressInfo(
      kind: LibraryChapterProgressKind.currentPage,
      isCurrent: true,
      currentPage: pageNumber,
      totalPages: images.length,
      fraction: pageNumber / images.length,
    );
  }

  @override
  Future<void> resetChapterReadingState({
    required String workId,
    required String episodeId,
  }) async {
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.comic,
      episodeId: episodeId,
      workId: workId,
      isRead: false,
      readAt: null,
    );
    final resetter = _repository is ComicReadingProgressResetter
        ? _repository as ComicReadingProgressResetter
        : null;
    await resetter?.clearReadingProgress(comicId: workId, episodeId: episodeId);
  }

  @override
  Future<void> resetWorkReadingState({required String workId}) async {
    final resetter = _repository is ComicWorkReadingStateResetter
        ? _repository as ComicWorkReadingStateResetter
        : null;
    if (resetter == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    await resetter.resetComicReadingState(comicId: workId);
  }

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {
    await _downloadQueue?.cancelEpisode(workId, episodeId);
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
    final queue = _downloadQueue;
    if (queue == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final detail = await _repository.getComicDetail(comicId: workId);
    final episodes = await _repository.getComicEpisodes(
      comicId: workId,
      descending: false,
    );
    await queue.enqueueTargets(
      episodes.map(
        (episode) => _downloadTarget(
          workId: workId,
          comicTitle: detail?.title,
          episode: episode,
        ),
      ),
    );
  }

  @override
  Future<void> downloadUnread({required String workId}) async {
    final queue = _downloadQueue;
    if (queue == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final detail = await _repository.getComicDetail(comicId: workId);
    final episodes = await _repository.getComicEpisodes(
      comicId: workId,
      descending: false,
    );
    final targets = <ComicDownloadTarget>[];
    for (final episode in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: episode.episodeId,
      );
      if (!(state?.isRead ?? false)) {
        targets.add(
          _downloadTarget(
            workId: workId,
            comicTitle: detail?.title,
            episode: episode,
          ),
        );
      }
    }
    await queue.enqueueTargets(targets);
  }

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    final episodes = await _repository.getComicEpisodes(
      comicId: workId,
      descending: false,
    );
    final orderedEpisodes = _episodeSequence.order(episodes);
    if (orderedEpisodes.isEmpty) {
      return null;
    }
    final targetEpisodeId = preferContinue
        ? await _resolveContinueEpisodeId(
            workId: workId,
            episodes: orderedEpisodes,
          )
        : orderedEpisodes.first.episodeId;
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
    final validEpisodeIds = episodes
        .map((episode) => episode.episodeId)
        .toSet();

    final progresses = await _repository.getReadingProgresses(comicId: workId);
    for (final progress in progresses) {
      if (!validEpisodeIds.contains(progress.episodeId)) {
        continue;
      }
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: progress.episodeId,
      );
      if (!(state?.isRead ?? false)) {
        return progress.episodeId;
      }
    }

    final workState = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.comic,
      workId: workId,
    );
    final stateEpisodeId = workState?.lastReadEpisodeId;
    if (stateEpisodeId != null && validEpisodeIds.contains(stateEpisodeId)) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: stateEpisodeId,
      );
      if (!(state?.isRead ?? false)) {
        return stateEpisodeId;
      }
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
  Future<ThreadRouteTarget?> getThreadRouteTarget({
    required String workId,
  }) async {
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
      final queue = _downloadQueue;
      if (queue == null) {
        throw const LibraryOperationException(
          LibraryOperationFailureCode.unsupported,
        );
      }
      final detail = await _repository.getComicDetail(comicId: workId);
      final episodes = await _repository.getComicEpisodes(
        comicId: workId,
        descending: false,
      );
      final episode = episodes
          .where((item) => item.episodeId == episodeId)
          .firstOrNull;
      if (episode == null) {
        throw const LibraryOperationException(
          LibraryOperationFailureCode.chapterNotFound,
        );
      }
      await queue.enqueueTargets(<ComicDownloadTarget>[
        _downloadTarget(
          workId: workId,
          comicTitle: detail?.title,
          episode: episode,
        ),
      ]);
      return;
    }
    await _downloadQueue?.cancelEpisode(workId, episodeId);
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

  ComicDownloadTarget _downloadTarget({
    required String workId,
    required String? comicTitle,
    required ComicEpisodeItem episode,
  }) {
    final normalizedComicTitle = comicTitle?.trim();
    final normalizedEpisodeTitle = episode.episodeTitle?.trim();
    return ComicDownloadTarget(
      comicId: workId,
      episodeId: episode.episodeId,
      comicTitle: normalizedComicTitle == null || normalizedComicTitle.isEmpty
          ? workId
          : normalizedComicTitle,
      episodeTitle:
          normalizedEpisodeTitle == null || normalizedEpisodeTitle.isEmpty
          ? episode.sourceTid
          : normalizedEpisodeTitle,
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
    final catalogUrl = detail.effectiveCatalogUrl;
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
          catalogUrl: _isBlank(detail.customCatalogUrl)
              ? direct.catalogUrl
              : null,
        );
        return DetailRefreshResult.immediate;
      }
    }

    // Step 2: catalog-only 目录路径。没有持久化 catalogUrl 时也必须先
    // 让统一 discovery 跑完整目录判断，再考虑当前帖增量和搜索队列。
    final catalog = await refreshService.fetchCatalogOnly(request);
    if (catalog.catalogMatched && catalog.hasLinks) {
      await _applyRefreshOutcome(
        applier: refreshOutcomeApplier,
        comicId: workId,
        sourceTid: detail.sourceTid,
        links: catalog.links,
        source: catalog.source,
        reason: 'comic_detail_catalog_refresh',
        catalogUrl: catalog.catalogUrl,
      );
      return DetailRefreshResult.immediate;
    }

    // Step 3: 获取当前帖详情（为增量发现提供解析数据）
    final parsedRoot = await _fetchAndParseCurrentThread(detail.sourceTid);

    // Step 3.5: catalogUrl 动态补全。fetchCatalogOnly 正常会覆盖这条路径；
    // 保留它是为了兼容测试/特殊 discovery service 只暴露 fetchAndParseThread。
    final discoveredCatalogUrl = parsedRoot?.catalogUrl;
    if (discoveredCatalogUrl != null && discoveredCatalogUrl.isNotEmpty) {
      // 持久化新发现的 catalogUrl，下次刷新可直接走快速路径
      await _repository.updateCatalogUrl(
        comicId: workId,
        catalogUrl: discoveredCatalogUrl,
      );
      // 立即尝试 catalog 快速路径
      final catalogRetry = await refreshService.fetchCatalogDirect(
        discoveredCatalogUrl,
      );
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

    // Step 6: catalog 和增量都无结果时才入搜索队列。
    final searchQueue = _searchQueue;
    if (searchQueue != null) {
      final queued = await searchQueue.enqueue(
        request: request,
        title: _queueTitle(detail),
        origin: ComicSearchRefreshOrigin.detailManual,
      );
      return DetailRefreshResult.queued(
        queuePosition: queued.position,
        estimatedDuration: queued.estimatedDuration,
      );
    }
    return const DetailRefreshResult(
      status: DetailRefreshStatus.skipped,
      outcomeCode: DetailRefreshOutcomeCode.noUpdates,
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
      customTitle: _featureFlags.readerCustomMetadataEnabled
          ? detail.customTitle
          : null,
      customSearchTitle: _featureFlags.readerCustomMetadataEnabled
          ? detail.customSearchTitle
          : null,
      catalogUrl: detail.effectiveCatalogUrl,
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
      final cleanBookName = _titleAnalyzer
          .analyze(displayTitle)
          .cleanBookName
          .trim();
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
  Future<DetailCatalogConfiguration> loadCatalogConfiguration({
    required String workId,
  }) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.workNotFound,
      );
    }
    return DetailCatalogConfiguration(
      sourceCatalogUrl: detail.catalogUrl,
      customCatalogUrl: detail.customCatalogUrl,
    );
  }

  @override
  Future<DetailCatalogUpdateOutcome> updateCatalogOverride({
    required String workId,
    String? catalogUrl,
  }) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.workNotFound,
      );
    }
    late final String? normalized;
    try {
      normalized = _catalogUrlPolicy.normalizeOverride(catalogUrl);
    } on ComicCatalogUrlInputException catch (error) {
      return DetailCatalogUpdateOutcome(
        code: DetailCatalogUpdateOutcomeCode.invalidInput,
        inputErrorCode: _mapCatalogInputError(error.code),
        expectedHost: error.expectedHost,
      );
    }
    String? source;
    try {
      source = _catalogUrlPolicy.normalizeOverride(detail.catalogUrl);
    } on ComicCatalogUrlInputException {
      source = null;
    }
    final repository = _repository;
    if (repository is! ComicCatalogOverrideRepository) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final catalogRepository = repository as ComicCatalogOverrideRepository;
    await catalogRepository.updateCustomCatalogUrl(
      comicId: workId,
      catalogUrl: normalized == source ? null : normalized,
    );
    return const DetailCatalogUpdateOutcome(
      code: DetailCatalogUpdateOutcomeCode.saved,
    );
  }

  @override
  Future<List<DetailManagedChapter>> loadManagedChapters({
    required String workId,
  }) async {
    final episodes = await _episodeManagementRepository.getManagedComicEpisodes(
      comicId: workId,
      descending: false,
    );
    // 与详情列表同一套排序：管理面板里的顺序必须和用户在列表上看到的一致，
    // 否则手动章节按 order_index 落到末尾会显得像插错了位置。
    final ordered = _episodeSequence.order(episodes);
    return ordered
        .map(
          (item) => DetailManagedChapter(
            episodeId: item.episodeId,
            title: item.episodeTitle?.trim().isNotEmpty == true
                ? item.episodeTitle!.trim()
                : '',
            // 来源名可能为空（早期解析没拿到标题），面板会退回展示同一个
            // 「章节 tid」兜底文案，避免提示成“清空后会变成空标题”。
            sourceTitle: item.sourceEpisodeTitle?.trim().isNotEmpty == true
                ? item.sourceEpisodeTitle!.trim()
                : null,
            customTitle: item.customEpisodeTitle?.trim().isNotEmpty == true
                ? item.customEpisodeTitle!.trim()
                : null,
            sourceTid: item.sourceTid,
            isManual: item.isManual,
            isHidden: item.isHidden,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<DetailManualChapterAddOutcome> addManualChapter({
    required String workId,
    required String input,
  }) async {
    late final ManualEpisodeTarget target;
    try {
      target = _manualEpisodeUrlPolicy.parse(input);
    } on ComicManualEpisodeInputException catch (error) {
      return DetailManualChapterAddOutcome(
        code: DetailManualChapterAddOutcomeCode.invalidInput,
        inputErrorCode: _mapManualChapterInputError(error.code),
        expectedHost: error.expectedHost,
      );
    }
    final added = await _episodeManagementRepository.addManualEpisode(
      comicId: workId,
      sourceTid: target.tid,
      sourceUrl: target.sourceUrl,
    );
    return DetailManualChapterAddOutcome(
      code: added
          ? DetailManualChapterAddOutcomeCode.added
          : DetailManualChapterAddOutcomeCode.duplicate,
    );
  }

  @override
  Future<DetailChapterRemovalResult> removeManualChapter({
    required String workId,
    required String episodeId,
  }) async {
    // 存储层先以 is_manual 做唯一准入判断并原子删除数据库状态；外部文件
    // 不属于 SQLite 事务，清理失败时保留“章节已移除”的事实并返回告警。
    final removal = await _episodeManagementRepository.removeManualEpisode(
      comicId: workId,
      episodeId: episodeId,
    );
    if (removal.code != ComicEpisodeRemovalCode.removed) {
      return DetailChapterRemovalResult(
        removed: false,
        rejectionCode: switch (removal.code) {
          ComicEpisodeRemovalCode.lastVisible =>
            DetailChapterRemovalRejectionCode.lastVisible,
          ComicEpisodeRemovalCode.notManual =>
            DetailChapterRemovalRejectionCode.notManual,
          ComicEpisodeRemovalCode.notFound =>
            DetailChapterRemovalRejectionCode.notFound,
          ComicEpisodeRemovalCode.removed => null,
        },
      );
    }
    final warnings = <DetailChapterRemovalWarningCode>{};
    try {
      await _downloadQueue?.cancelEpisode(workId, episodeId);
    } catch (error) {
      warnings.add(DetailChapterRemovalWarningCode.downloadTaskCleanupFailed);
      debugPrint('[ComicEpisodeManagement] cancel download failed: $error');
    }
    try {
      await _downloadService?.deleteEpisodeDownload(
        comicId: workId,
        episodeId: episodeId,
      );
    } catch (error) {
      warnings.add(DetailChapterRemovalWarningCode.downloadFileCleanupFailed);
      debugPrint('[ComicEpisodeManagement] delete download failed: $error');
    }
    return DetailChapterRemovalResult(
      removed: true,
      warnings: Set<DetailChapterRemovalWarningCode>.unmodifiable(warnings),
    );
  }

  @override
  Future<DetailChapterVisibilityUpdateResult> setChapterHidden({
    required String workId,
    required String episodeId,
    required bool isHidden,
  }) async {
    final result = await _episodeManagementRepository.setEpisodeHidden(
      comicId: workId,
      episodeId: episodeId,
      isHidden: isHidden,
    );
    return DetailChapterVisibilityUpdateResult(
      code: switch (result.code) {
        ComicEpisodeVisibilityUpdateCode.updated =>
          DetailChapterVisibilityUpdateCode.updated,
        ComicEpisodeVisibilityUpdateCode.rejectedLastVisible =>
          DetailChapterVisibilityUpdateCode.rejectedLastVisible,
        ComicEpisodeVisibilityUpdateCode.notFound =>
          DetailChapterVisibilityUpdateCode.notFound,
      },
    );
  }

  @override
  Future<void> renameChapter({
    required String workId,
    required String episodeId,
    required String? customTitle,
  }) async {
    await _episodeManagementRepository.setEpisodeCustomTitle(
      comicId: workId,
      episodeId: episodeId,
      customTitle: customTitle,
    );
  }

  ComicEpisodeManagementRepository get _episodeManagementRepository {
    final repository = _repository;
    if (repository is! ComicEpisodeManagementRepository) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    return repository as ComicEpisodeManagementRepository;
  }

  @override
  bool canRemoveCover(LibraryDetailHeader header) {
    return header.coverAsset?.kind == LibraryCoverAssetKind.custom ||
        _hasCoverValue(header.customCoverLocalPath) ||
        _hasCoverValue(header.customCoverImageUrl);
  }

  bool _hasCoverValue(String? value) => value?.trim().isNotEmpty ?? false;

  @override
  Future<void> setCustomCoverFromLocalFile({
    required String workId,
    required String sourceLocalPath,
    double? focusX,
    double? focusY,
  }) async {
    final store = _coverStore;
    final repository = _repository;
    if (store == null || repository is! ComicCustomCoverAssetWriter) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.unsupported,
      );
    }
    final assetWriter = repository as ComicCustomCoverAssetWriter;
    final detail = await repository.getComicDetail(comicId: workId);
    final revision = (detail?.customCoverRevision ?? 0) + 1;
    final asset = LibraryCoverAssetRef(
      assetId: LibraryCoverAssetIds.custom(
        ownerType: 'comic',
        ownerId: workId,
      ),
      revision: revision,
      kind: LibraryCoverAssetKind.custom,
    );
    await store.installLocalFile(asset: asset, sourcePath: sourceLocalPath);
    try {
      await assetWriter.activateCustomCoverAsset(
        comicId: workId,
        revision: revision,
        focusX: focusX,
        focusY: focusY,
      );
    } catch (_) {
      await store.invalidate(asset);
      rethrow;
    }
    await store.deleteOlderRevisions(asset);
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String workId,
    required double? focusX,
    required double? focusY,
  }) {
    return _repository.updateCustomCoverFocus(
      comicId: workId,
      focusX: focusX,
      focusY: focusY,
    );
  }

  @override
  Future<void> removeCustomCover({required String workId}) async {
    await _repository.updateCustomCover(
      comicId: workId,
      customCoverImageUrl: null,
    );
    await _coverStore?.deleteAsset(
      LibraryCoverAssetIds.custom(ownerType: 'comic', ownerId: workId),
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

  Future<String?> _findCurrentCategoryId(String workId) async {
    final categories = await _repository.getCategories();
    for (final category in categories) {
      final works = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      if (works.any((item) => item.comicId == workId)) {
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
      var result = compareLibrarySourceIds(a.sourceTid, b.sourceTid);
      if (result == 0) {
        result = a.orderIndex.compareTo(b.orderIndex);
      }
      if (result == 0) {
        result = a.episodeId.compareTo(b.episodeId);
      }
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
}

DetailCatalogInputErrorCode _mapCatalogInputError(
  ComicCatalogUrlInputErrorCode code,
) {
  return switch (code) {
    ComicCatalogUrlInputErrorCode.invalidUrl =>
      DetailCatalogInputErrorCode.invalidUrl,
    ComicCatalogUrlInputErrorCode.incompleteUrl =>
      DetailCatalogInputErrorCode.incompleteUrl,
    ComicCatalogUrlInputErrorCode.unsupportedScheme =>
      DetailCatalogInputErrorCode.unsupportedScheme,
    ComicCatalogUrlInputErrorCode.unexpectedHost =>
      DetailCatalogInputErrorCode.unexpectedHost,
    ComicCatalogUrlInputErrorCode.notTagCatalog =>
      DetailCatalogInputErrorCode.notTagCatalog,
  };
}

DetailManualChapterInputErrorCode _mapManualChapterInputError(
  ComicManualEpisodeInputErrorCode code,
) {
  return switch (code) {
    ComicManualEpisodeInputErrorCode.emptyInput =>
      DetailManualChapterInputErrorCode.emptyInput,
    ComicManualEpisodeInputErrorCode.invalidUrl =>
      DetailManualChapterInputErrorCode.invalidUrl,
    ComicManualEpisodeInputErrorCode.unsupportedScheme =>
      DetailManualChapterInputErrorCode.unsupportedScheme,
    ComicManualEpisodeInputErrorCode.unexpectedHost =>
      DetailManualChapterInputErrorCode.unexpectedHost,
    ComicManualEpisodeInputErrorCode.unsupportedThreadUrl =>
      DetailManualChapterInputErrorCode.unsupportedThreadUrl,
    ComicManualEpisodeInputErrorCode.missingTid =>
      DetailManualChapterInputErrorCode.missingTid,
  };
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;
