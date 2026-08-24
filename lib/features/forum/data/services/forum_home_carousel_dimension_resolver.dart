import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/forum/domain/services/forum_chrome_image_adapter.dart';

/// Restores App-owned carousel layout metadata without performing a network
/// request. The dimension index prefers the current cache key, then the latest
/// dimensions recorded for the same forum-home image owner.
final class ForumHomeCarouselDimensionResolver {
  const ForumHomeCarouselDimensionResolver({
    required ForumImageDimensionIndex dimensionIndex,
  }) : _dimensionIndex = dimensionIndex;

  static const double fallbackAspectRatio = 3.45;

  final ForumImageDimensionIndex _dimensionIndex;

  Future<double?> resolveAspectRatio(String imageUrl) async {
    final spec = const ForumChromeImageAdapter().carouselImage(imageUrl);
    if (spec == null) {
      return null;
    }
    try {
      final dimensions = await _dimensionIndex.getLastKnownBySpec(spec);
      final aspectRatio = dimensions?.aspectRatio;
      if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
        return null;
      }
      return aspectRatio;
    } catch (_) {
      // Layout metadata is an optimization; cache failures must not block the
      // forum home document from being displayed.
      return null;
    }
  }
}
