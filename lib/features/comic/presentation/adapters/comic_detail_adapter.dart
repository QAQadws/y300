import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 漫画详情适配器（Phase 0 骨架版）。
class ComicDetailAdapter implements DetailModuleAdapter {
  ComicDetailAdapter(this._repository);

  final ComicRepository _repository;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    final detail = await _repository.getComicDetail(comicId: workId);
    if (detail == null) {
      throw StateError('漫画不存在或已删除');
    }
    final inShelf = await _repository.isInShelf(comicId: workId);
    return LibraryDetailHeader(
      workId: detail.comicId,
      title: detail.title,
      coverImageUrl: detail.coverImageUrl,
      author: detail.author,
      translationGroup: detail.translationGroup,
      sourceTid: detail.sourceTid,
      inShelf: inShelf,
    );
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    // Phase 0：先返回基础章节数据，不引入新状态位筛选。
    final descending = sortOption.direction == LibrarySortDirection.desc;
    final episodes = await _repository.getComicEpisodes(
      comicId: workId,
      descending: descending,
    );
    return episodes
        .map(
          (item) => LibraryChapterItem(
            episodeId: item.episodeId,
            workId: item.comicId,
            title: item.episodeTitle?.trim().isNotEmpty == true
                ? item.episodeTitle!
                : '章节 ${item.sourceTid}',
            orderIndex: item.orderIndex,
            sourceTid: item.sourceTid,
            publishTimeText: item.publishTimeText,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> clearAllReadState({required String workId}) async {}

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {}

  @override
  Future<void> downloadAll({required String workId}) async {}

  @override
  Future<void> downloadUnread({required String workId}) async {}

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
  }) async {}

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) async {}

  @override
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  }) async {}

  @override
  Future<void> refreshWork({required String workId}) async {}

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}
}

