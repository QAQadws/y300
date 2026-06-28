import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';

class StickerImageSource {
  const StickerImageSource({
    required this.normalizedPath,
    required this.url,
    required this.cacheKey,
  });

  final String normalizedPath;
  final String url;
  final String cacheKey;
}

/// Normalizes Yamibo smiley image references from API payloads, HTML `src`
/// attributes and local preview paths into the shared `remoteSmiley` cache key.
class StickerImageResolver {
  const StickerImageResolver();

  StickerImageSource resolve(String source) {
    final normalizedPath = ImageCacheKeys.normalizeRemoteSmileyPath(source);
    return StickerImageSource(
      normalizedPath: normalizedPath,
      url: imageUrlForPath(normalizedPath),
      cacheKey: ImageCacheKeys.remoteSmiley(normalizedPath),
    );
  }

  String imageUrlForPath(String normalizedPath) {
    return Uri.parse(
      AppConfig.siteBaseUrl,
    ).replace(path: '/static/image/smiley/$normalizedPath').toString();
  }
}
