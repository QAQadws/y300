import 'package:y300/features/cache/domain/image_cache_models.dart';

class ReaderImageSource {
  const ReaderImageSource({
    required this.url,
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    required this.role,
    required this.retentionClass,
    required this.index,
  });

  final String url;
  final String cacheKey;
  final ImageCacheOwnerType ownerType;
  final String ownerId;
  final ImageCacheRole role;
  final ImageRetentionClass retentionClass;
  final int index;

  ImageCacheRequest toCacheRequest({ImageRetentionClass? retentionOverride}) {
    final retention = retentionOverride ?? retentionClass;
    return ImageCacheRequest(
      cacheKey: cacheKey,
      sourceUrl: url,
      ownerType: ownerType,
      ownerId: ownerId,
      role: role,
      imageIndex: index,
      retentionClass: retention,
      protected:
          retention == ImageRetentionClass.protected ||
          retention == ImageRetentionClass.downloaded,
    );
  }
}

abstract class ReaderImageCacheLifecycleService {
  Future<void> markRecentlyRead(ReaderImageSource source);

  Future<void> promoteToComicPage({
    required ReaderImageSource source,
    required String comicId,
    required String episodeId,
    required int imageIndex,
  });
}
