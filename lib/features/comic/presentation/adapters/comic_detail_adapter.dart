import 'package:y300/features/comic/data/comic_repository.dart';
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
class ComicDetailAdapter implements DetailModuleAdapter {
  ComicDetailAdapter(
    this._repository, {
    ComicEpisodeRefreshService? refreshService,
    required LibraryStateRepository stateRepository,
  })  : _refreshService = refreshService,
        _stateRepository = stateRepository;

  final ComicRepository _repository;
  final ComicEpisodeRefreshService? _refreshService;
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
    var coverImageUrl = detail.coverImageUrl;
    if (coverImageUrl == null || coverImageUrl.trim().isEmpty) {
      // Phase 6：漫画封面兜底优先尝试“首话首图”。
      final episodes = await _repository.getComicEpisodes(comicId: workId, descending: false);
      if (episodes.isNotEmpty) {
        final images = await _repository.getEpisodeImages(episodeId: episodes.first.episodeId);
        if (images.isNotEmpty) {
          coverImageUrl = images.first.imageUrl;
        }
      }
    }
    return LibraryDetailHeader(
      workId: detail.comicId,
      title: detail.title,
      coverImageUrl: coverImageUrl,
      author: detail.author,
      translationGroup: detail.translationGroup,
      sourceTid: detail.sourceTid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      customTags: customTags,
      inShelf: inShelf,
      intro: workState?.introText,
    );
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
    final target = preferContinue ? episodes.last : episodes.first;
    return ReaderRouteTarget(workId: workId, episodeId: target.episodeId);
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
    final links = await refreshService.fetchEpisodeLinksFromTid(detail.sourceTid);
    if (links.isEmpty) {
      return;
    }
    await _repository.mergeEpisodesFromLinks(
      comicId: workId,
      episodeLinks: links,
      fallbackSourceTid: detail.sourceTid,
    );
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
