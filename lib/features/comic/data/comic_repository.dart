import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

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
