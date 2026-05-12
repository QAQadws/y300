import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 漫画仓库：封装书架数据访问，屏蔽具体存储实现。
abstract class ComicRepository {
  Future<List<ComicShelfCategory>> getCategories();

  Future<String> createCategory({required String name});

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  });

  Future<void> deleteCategory({required String categoryId});

  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  });

  Future<ComicShelfDisplaySettings> getDisplaySettings();

  Future<void> updateGridColumnCount({required int columnCount});

  Future<void> updateCustomCover({
    required String comicId,
    required String? customCoverImageUrl,
  });

  Future<bool> isInShelf({required String comicId});

  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  });

  /// 从漫画书架移除作品，但保留作品、章节和阅读缓存。
  ///
  /// 收藏同步取消收藏时只改变“是否在书架”，不应静默删除用户已产生的
  /// 阅读进度、图片缓存或后续下载存储。
  Future<void> removeFromShelf({required String comicId});

  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  });

  Future<ComicDetail?> getComicDetail({required String comicId});

  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  });

  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  });

  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  });

  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  });

  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  });

  Future<ComicReadingProgress?> getLastReadProgress({
    required String comicId,
  });

  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  });
}

abstract class ComicShelfSnapshotRepository {
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });
}

/// 单个漫画作品在书架上的章节状态聚合。
///
/// 聚合口径以章节表为主：章节存在但还没有 `library_episode_state` 行时，
/// 默认视为未读。这个模型用于没有走 snapshot 批量查询时的适配器 fallback。
class ComicShelfWorkStats {
  const ComicShelfWorkStats({
    required this.totalCount,
    required this.unreadCount,
    required this.readCount,
    required this.downloadedCount,
  });

  final int totalCount;
  final int unreadCount;
  final int readCount;
  final int downloadedCount;
}

abstract class ComicShelfStatsRepository {
  Future<ComicShelfWorkStats> getShelfWorkStats({
    required String comicId,
  });
}

abstract class ComicCoverCacheWriter {
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  });
}

abstract class ComicEpisodeImageCacheMetadataWriter {
  Future<void> updateEpisodeImageCacheMetadata({
    required String episodeId,
    required String imageUrl,
    String? stableCacheKey,
    String? lastSourceUrl,
    String? localPath,
    int? bytes,
    String? mimeType,
    DateTime? lastAccessedAt,
    bool? protected,
  });
}
