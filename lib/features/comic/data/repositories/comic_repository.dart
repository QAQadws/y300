import 'package:y300/features/comic/data/services/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// Optional persistence capability for clearing one comic chapter's saved
/// image position. Keeping this separate avoids forcing non-SQLite test and
/// remote repository implementations to expose storage-specific behavior.
abstract interface class ComicReadingProgressResetter {
  Future<void> clearReadingProgress({
    required String comicId,
    required String episodeId,
  });
}

/// 漫画仓库：封装书架数据访问，屏蔽具体存储实现。
abstract class ComicRepository implements CatalogUrlUpdater {
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

  Future<void> updateCustomCoverFromLocalFile({
    required String comicId,
    required String localCoverPath,
    String? sourceEpisodeId,
    int? sourceImageIndex,
    String? sourceImageUrl,
    double? focusX,
    double? focusY,
  });

  /// 仅更新已有自定义封面的焦点（不改封面文件），用于详情页“调整封面焦点”。
  Future<void> updateCustomCoverFocus({
    required String comicId,
    required double? focusX,
    required double? focusY,
  });

  Future<void> updateCustomMetadata({
    required String comicId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  });

  Future<void> clearCustomMetadata({
    required String comicId,
    bool title = false,
    bool author = false,
    bool translationGroup = false,
    bool searchTitle = false,
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

  /// 破坏性清除漫画作品的本地数据。
  ///
  /// 与 [removeFromShelf] 不同：这里会删除作品主行，由数据库级联清除章节、
  /// 章节图片、书架项和阅读进度记录。缓存、下载、shared 状态与收藏行由
  /// 上层 WorkPurgeService 继续编排。
  Future<void> purgeWork({required String comicId}) {
    throw UnimplementedError('purgeWork($comicId)');
  }

  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'});

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

  Future<void> clearEpisodeImageCache({required String episodeId});

  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  });

  Future<ComicReadingProgress?> getLastReadProgress({required String comicId});

  Future<ComicReadingProgress?> getReadingProgressForEpisode({
    required String comicId,
    required String episodeId,
  }) async {
    final progress = await getLastReadProgress(comicId: comicId);
    return progress?.episodeId == episodeId ? progress : null;
  }

  /// Returns all persisted chapter progress rows, newest visit first.
  Future<List<ComicReadingProgress>> getReadingProgresses({
    required String comicId,
  }) async {
    final progress = await getLastReadProgress(comicId: comicId);
    return progress == null
        ? const <ComicReadingProgress>[]
        : <ComicReadingProgress>[progress];
  }

  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  });

  /// 更新漫画的目录 URL（catalogUrl）。
  ///
  /// 用于 catalog 快速路径：首次发现或更新时持久化，
  /// 下次刷新可直接解析 catalog HTML 而不请求帖子详情。
  @override
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  });

  /// 获取本地已知章节的 sourceTid 集合。
  ///
  /// 用于增量章节发现：与帖子内解析出的链接做差集，
  /// 快速识别新增章节而无需全量比对。
  Future<Set<String>> getKnownEpisodeTids({required String comicId});
}

/// 用户目录覆盖值的可选持久化能力。
///
/// 与解析发现的 [CatalogUrlUpdater] 分离，避免自动来源更新覆盖用户配置。
abstract class ComicCatalogOverrideRepository {
  Future<void> updateCustomCatalogUrl({
    required String comicId,
    required String? catalogUrl,
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
  Future<ComicShelfWorkStats> getShelfWorkStats({required String comicId});
}

abstract class ComicCoverCacheWriter {
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  });
}

abstract class ComicFirstEpisodeCoverWriter {
  Future<bool> promoteFirstEpisodeCover({
    required String comicId,
    required String episodeId,
    required String imageUrl,
  });
}

abstract class ComicEpisodeImageCacheMetadataWriter {
  Future<void> updateEpisodeImageCacheMetadata({
    required String episodeId,
    required String imageUrl,
    String? stableCacheKey,
    String? lastSourceUrl,
    String? localPath,
    int? width,
    int? height,
    int? bytes,
    String? mimeType,
    DateTime? lastAccessedAt,
    bool? protected,
  });
}

class ComicDuplicateGroup {
  const ComicDuplicateGroup({required this.comicIds, required this.sharedTids});

  final Set<String> comicIds;
  final Set<String> sharedTids;
}

class ComicDuplicateMergeResult {
  const ComicDuplicateMergeResult({
    required this.targetComicId,
    required this.targetTitle,
    required this.mergedComicIds,
    required this.replacements,
    required this.movedEpisodeCount,
  });

  const ComicDuplicateMergeResult.unchanged({required this.targetComicId})
    : targetTitle = null,
      mergedComicIds = const <String>{},
      replacements = const <String, String>{},
      movedEpisodeCount = 0;

  final String targetComicId;
  final String? targetTitle;
  final Set<String> mergedComicIds;
  final Map<String, String> replacements;
  final int movedEpisodeCount;

  bool get changed => mergedComicIds.isNotEmpty;
}

class ComicDuplicateMergeSummary {
  const ComicDuplicateMergeSummary({
    required this.mergedGroupCount,
    required this.removedComicCount,
    required this.movedEpisodeCount,
    required this.replacements,
  });

  const ComicDuplicateMergeSummary.empty()
    : mergedGroupCount = 0,
      removedComicCount = 0,
      movedEpisodeCount = 0,
      replacements = const <String, String>{};

  final int mergedGroupCount;
  final int removedComicCount;
  final int movedEpisodeCount;
  final Map<String, String> replacements;

  bool get changed => removedComicCount > 0;

  ComicDuplicateMergeSummary combine(ComicDuplicateMergeResult result) {
    if (!result.changed) {
      return this;
    }
    return ComicDuplicateMergeSummary(
      mergedGroupCount: mergedGroupCount + 1,
      removedComicCount: removedComicCount + result.mergedComicIds.length,
      movedEpisodeCount: movedEpisodeCount + result.movedEpisodeCount,
      replacements: <String, String>{...replacements, ...result.replacements},
    );
  }
}

abstract class ComicDuplicateMergeRepository {
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId});

  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  });
}
