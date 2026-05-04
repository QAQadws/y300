import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

/// 小说详情适配器（Phase 0 骨架版）。
class NovelDetailAdapter implements DetailModuleAdapter {
  NovelDetailAdapter(this._repository);

  final NovelRepository _repository;

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
    final descending = sortOption.direction == LibrarySortDirection.desc;
    final episodes = await _repository.getEpisodes(
      novelId: workId,
      descending: descending,
    );
    return episodes
        .map(
          (item) => LibraryChapterItem(
            episodeId: item.episodeId,
            workId: item.novelId,
            title: item.episodeTitle,
            orderIndex: item.orderIndex,
            sourceTid: item.sourceTid,
            publishTimeText: item.datelineText,
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
  Future<void> refreshWork({required String workId}) async {
    await _repository.refreshEpisodes(novelId: workId);
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}
}

