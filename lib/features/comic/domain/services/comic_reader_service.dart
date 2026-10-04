import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';

abstract class ComicReaderService {
  /// 拉取单话首楼图片，区分"成功（含真无图）"和各类失败原因。
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid);

  Future<ComicImageCacheResult> cacheImage({
    required String imageUrl,
    String? cacheKey,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
    ImageCacheRole role = ImageCacheRole.comicPage,
    String? episodeId,
    int? imageIndex,
    bool protected = false,
  });

  Future<void> prefetchImages({required List<String> imageUrls}) async {
    for (final imageUrl in imageUrls) {
      await cacheImage(imageUrl: imageUrl);
    }
  }
}

class ComicImageCacheResult {
  const ComicImageCacheResult({
    required this.success,
    this.localPath,
    this.cacheKey,
    this.bytes = 0,
    this.fromCache = false,
  });

  final bool success;
  final String? localPath;
  final String? cacheKey;
  final int bytes;
  final bool fromCache;
}
