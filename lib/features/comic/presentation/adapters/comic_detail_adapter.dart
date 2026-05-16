import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 漫画详情适配器（Phase 6）。
///
/// 负责把漫画仓储数据映射到统一详情模型，并接入章节状态筛选/排序。
/// 刷新能力通过 ComicEpisodeRefreshService 下沉到漫画域 services，
/// 保证统一详情页只保留编排，不耦合漫画刷新策略细节。
class ComicDetailAdapter implements DetailModuleAdapter, DetailMetadataEditor {
  ComicDetailAdapter(
    this._repository, {
    ComicEpisodeRefreshService? refreshService,
    ComicFirstEpisodeCoverService? firstEpisodeCoverService,
    ComicDownloadService? downloadService,
    ImageCacheService? imageCacheService,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
    required LibraryStateRepository stateRepository,
  })  : _refreshService = refreshService,
        _firstEpisodeCoverService = firstEpisodeCoverService,
        _downloadService = downloadService,
        _imageCacheService = imageCacheService,
        _featureFlags = featureFlags,
        _stateRepository = stateRepository;

  final ComicRepository _repository;
  final ComicEpisodeRefreshService? _refreshService;
  final ComicFirstEpisodeCoverService? _firstEpisodeCoverService;
  final ComicDownloadService? _downloadService;
  final ImageCacheService? _imageCacheService;
  final ComicReaderFeatureFlags _featureFlags;
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

    final mapped = <LibraryChapterItem>[];
    for (final item in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: item.episodeId,
      );
      mapped.add(
        LibraryChapterItem(
          episodeId: item.episodeId,
          workId: item.comicId,
          title: item.episodeTitle?.trim().isNotEmpty == true ? item.episodeTitle! : '章节 ${item.sourceTid}',
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          publishTimeText: item.publishTimeText,
          isRead: state?.isRead ?? false,
          isDownloaded: state?.isDownloaded ?? false,
          isBookmarked: state?.isBookmarked ?? false,
        ),
      );
    }

    final filtered = _applyFilters(mapped, filters);
    return _sortChapters(filtered, sortOption);
  }

  @override
  Future<void> clearAllReadState({required String workId}) async {
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
  Future<void> refreshWork({required String workId}) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      return;
    }
    final refreshService = _refreshService;
    if (refreshService == null) {
      return;
    }
    final links = await refreshService.fetchEpisodeLinks(
      ComicEpisodeRefreshRequest(
        comicId: detail.comicId,
        sourceTid: detail.sourceTid,
        displayTitle: detail.displayTitle,
        sourceTitle: detail.sourceTitle,
        customTitle:
            _featureFlags.readerCustomMetadataEnabled ? detail.customTitle : null,
        customSearchTitle: _featureFlags.readerCustomMetadataEnabled
            ? detail.customSearchTitle
            : null,
      ),
    );
    if (links.isEmpty) {
      return;
    }
    await _repository.mergeEpisodesFromLinks(
      comicId: workId,
      episodeLinks: links,
      fallbackSourceTid: detail.sourceTid,
    );
    await _firstEpisodeCoverService?.promoteIfPossible(comicId: workId);
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

