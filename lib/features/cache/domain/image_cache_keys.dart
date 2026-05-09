/// Stable logical image cache keys shared by comics, novels and future modules.
///
/// These keys intentionally do not contain transient remote URLs.  The remote
/// URL is only the last known source used to populate the local file.
abstract final class ImageCacheKeys {
  static String comicCover(String comicId) {
    return 'cover/comic/${_normalizePart(comicId)}';
  }

  static String novelCover(String novelId) {
    return 'cover/novel/${_normalizePart(novelId)}';
  }

  static String comicPage({
    required String comicId,
    required String episodeId,
    required int imageIndex,
  }) {
    return 'comic/${_normalizePart(comicId)}/${_normalizePart(episodeId)}/${_padIndex(imageIndex)}';
  }

  static String novelInline({
    required String novelId,
    required String episodeId,
    required int imageIndex,
  }) {
    return 'novel/${_normalizePart(novelId)}/${_normalizePart(episodeId)}/${_padIndex(imageIndex)}';
  }

  static String customCover({
    required String ownerType,
    required String ownerId,
  }) {
    return 'cover/custom/${_normalizePart(ownerType)}/${_normalizePart(ownerId)}';
  }

  static String _padIndex(int value) {
    final normalized = value < 0 ? 0 : value;
    return normalized.toString().padLeft(3, '0');
  }

  static String _normalizePart(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }
}
