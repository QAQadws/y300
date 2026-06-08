import 'package:y300/features/novel/data/models/novel_models.dart';

import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 小说仓储：封装小说书架、章节、正文、阅读偏好与阅读进度。
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

  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences);

  Future<NovelReaderPreferences> getReaderPreferences();

  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed});

  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId});

  /// 从小说书架移除作品，但保留作品数据和已缓存章节正文。
  Future<void> removeFromShelf({required String novelId});

  /// 破坏性清除小说作品的本地数据。
  ///
  /// 这里删除小说主行、章节、正文和小说侧阅读进度；shared 状态、收藏行、
  /// 缓存和下载由上层 WorkPurgeService 继续编排。
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
