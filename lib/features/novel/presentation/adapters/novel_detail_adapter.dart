import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

/// 小说详情适配器（Phase 5）。
class NovelDetailAdapter implements DetailModuleAdapter {
  NovelDetailAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
  }) : _stateRepository = stateRepository;

  final NovelRepository _repository;
  final LibraryStateRepository _stateRepository;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    final detail = await _repository.getDetail(novelId: workId);
    if (detail == null) {
      throw StateError('小说不存在或已删除');
    }
    return LibraryDetailHeader(
      workId: detail.novelId,
      title: detail.title,
      coverImageUrl: detail.coverImageUrl,
      author: detail.author,
      sourceTid: detail.sourceTid,
      inShelf: true,
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
    if (preferContinue && progress != null) {
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
  Future<void> refreshWork({required String workId}) async {
    await _repository.refreshEpisodes(novelId: workId);
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}

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
