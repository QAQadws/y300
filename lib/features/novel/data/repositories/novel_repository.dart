import 'package:y300/features/novel/data/models/novel_models.dart';

import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

/// 小说仓储：封装小说书架、章节、正文与阅读业务状态。
abstract class NovelRepository {
  Future<List<NovelShelfCategory>> getCategories();

  Future<String> createCategory({required String name});

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  });

  Future<void> deleteCategory({required String categoryId});

  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  });

  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'});

  Future<NovelItem?> getDetail({required String novelId});

  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  });

  Future<NovelChapterContent?> getChapterContent({required String episodeId});

  /// 从小说书架移除作品，但保留作品数据和已水合章节正文。
  Future<void> removeFromShelf({required String novelId});

  /// 破坏性清除小说作品的本地数据。
  ///
  /// 这里删除小说主行、章节、正文和小说侧阅读进度；shared 状态、收藏行、
  /// 封面缓存和遗留下载目录由上层 WorkPurgeService 继续编排。
  Future<void> purgeWork({required String novelId}) {
    throw UnimplementedError('purgeWork($novelId)');
  }

  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  });

  Future<NovelReadingProgress?> getReadingProgress({required String novelId});

  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  });

  Future<void> addReaderBookmark({required NovelReaderBookmark bookmark});

  Future<void> removeReaderBookmark({required String bookmarkId});

  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  });
}

abstract class NovelShelfSnapshotRepository {
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });
}

abstract class NovelCoverCacheWriter {
  Future<void> updateCoverCache({
    required String novelId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  });
}

/// 小说用户元数据写入能力。
///
/// 来源标题和发布者继续由收藏同步维护；这里仅保存用户标题覆盖值。
abstract class NovelCustomMetadataWriter {
  Future<void> updateCustomMetadata({
    required String novelId,
    String? customTitle,
  });
}

/// 小说自定义封面写入能力。
abstract class NovelCustomCoverWriter {
  Future<void> updateCustomCover({
    required String novelId,
    required String customCoverLocalPath,
    double? focusX,
    double? focusY,
  });

  Future<void> updateCustomCoverFocus({
    required String novelId,
    double? focusX,
    double? focusY,
  });

  /// 隐藏当前封面并清除自定义封面；来源同步不得恢复显示。
  Future<void> removeCustomCover({required String novelId});
}
