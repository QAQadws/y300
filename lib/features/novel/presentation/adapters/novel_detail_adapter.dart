import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

/// 小说详情适配器（Phase 6）。
class NovelDetailAdapter implements DetailModuleAdapter {
  NovelDetailAdapter(
    this._repository, {
    NovelDownloadService? downloadService,
    required LibraryStateRepository stateRepository,
  })  : _downloadService = downloadService,
        _stateRepository = stateRepository;

  final NovelRepository _repository;
  final NovelDownloadService? _downloadService;
  final LibraryStateRepository _stateRepository;

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
    final customTags = await _stateRepository.getWorkTags(
      moduleKey: LibraryModuleKey.novel,
      workId: workId,
    );
    return LibraryDetailHeader(
      workId: detail.novelId,
      title: detail.title,
      coverImageUrl: detail.coverImageUrl,
      coverLocalPath: detail.coverLocalPath,
      customCoverLocalPath: detail.customCoverLocalPath,
      author: detail.author,
      sourceTid: detail.sourceTid,
      sourceTypeId: detail.sourceTypeId,
      sourceTagName: detail.sourceTagName,
      customTags: customTags,
      inShelf: true,
      intro: workState?.introText,
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

    final mapped = <LibraryChapterItem>[];
    for (final item in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: item.episodeId,
      );
      mapped.add(
        LibraryChapterItem(
          episodeId: item.episodeId,
          workId: item.novelId,
          title: item.episodeTitle,
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          sourcePid: item.sourcePid,
          publishTimeText: item.datelineText,
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
    final episodes = await _repository.getEpisodes(novelId: workId, descending: false);
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
    final episodes = await _repository.getEpisodes(novelId: workId, descending: false);
    for (final episode in episodes) {
      await markChapterDownloaded(workId: workId, episodeId: episode.episodeId, isDownloaded: true);
    }
  }

  @override
  Future<void> downloadUnread({required String workId}) async {
    final episodes = await _repository.getEpisodes(novelId: workId, descending: false);
    for (final episode in episodes) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.novel,
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
    final progress = await _repository.getReadingProgress(novelId: workId);
    final episodes = await _repository.getEpisodes(novelId: workId, descending: false);
    if (episodes.isEmpty) {
      return null;
    }
    if (preferContinue &&
        progress != null &&
        episodes.any((episode) => episode.episodeId == progress.episodeId)) {
      return ReaderRouteTarget(workId: workId, episodeId: progress.episodeId);
    }
    return ReaderRouteTarget(workId: workId, episodeId: episodes.first.episodeId);
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({required String workId}) async {
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
    await _repository.refreshEpisodes(novelId: workId);
    return DetailRefreshResult.immediate;
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

  @override
  Future<List<LibraryTag>> getWorkTags({required String workId}) {
    return _stateRepository.getWorkTags(
      moduleKey: LibraryModuleKey.novel,
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
      moduleKey: LibraryModuleKey.novel,
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
      moduleKey: LibraryModuleKey.novel,
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
      moduleKey: LibraryModuleKey.novel,
      workId: workId,
      tagId: tagId,
    );
  }

  Future<String?> _findCurrentCategoryId(String workId) async {
    final categories = await _repository.getCategories();
    for (final category in categories) {
      final works = await _repository.getShelfItems(categoryId: category.categoryId);
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
        LibraryChapterSortField.tid => _compareNumericText(a.sourcePid ?? '', b.sourcePid ?? ''),
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

  int _compareNumericText(String a, String b) {
    final aNumber = int.tryParse(a);
    final bNumber = int.tryParse(b);
    if (aNumber != null && bNumber != null) {
      return aNumber.compareTo(bNumber);
    }
    return a.compareTo(b);
  }
}
