import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/forum/domain/services/forum_chrome_image_adapter.dart';

/// Restores App-owned carousel layout metadata without performing a network
/// request. The dimension index prefers the current cache key, then the latest
/// dimensions recorded for the same forum-home image owner.
final class ForumHomeCarouselDimensionResolver {
  const ForumHomeCarouselDimensionResolver({
    required ForumImageDimensionIndex dimensionIndex,
    SharedPreferencesLoader? preferencesLoader,
  }) : _dimensionIndex = dimensionIndex,
       _preferencesLoader = preferencesLoader;

  static const double fallbackAspectRatio = 3.45;

  final ForumImageDimensionIndex _dimensionIndex;
  final SharedPreferencesLoader? _preferencesLoader;

  Future<SharedPreferences> _preferences() =>
      (_preferencesLoader ?? SharedPreferences.getInstance)();

  /// The cached first frame must not join the library database queue just to
  /// restore image layout. This exact-URL hint is filled by background loads.
  Future<double?> resolveCachedAspectRatio(String imageUrl) async {
    try {
      final raw = (await _preferences()).getString(
        TechnicalStorageKeys.forumHomeCarouselLayoutV1,
      );
      if (raw == null) return null;
      final value = jsonDecode(raw) as Map;
      if (value['url'] != imageUrl) return null;
      final ratio = (value['ratio'] as num).toDouble();
      return ratio.isFinite && ratio > 0 ? ratio : null;
    } catch (_) {
      return null;
    }
  }

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
      try {
        await (await _preferences()).setString(
          TechnicalStorageKeys.forumHomeCarouselLayoutV1,
          jsonEncode({'url': imageUrl, 'ratio': aspectRatio}),
        );
      } catch (_) {
        // This optional hint is independent of the image cache lifecycle.
      }
      return aspectRatio;
    } catch (_) {
      // Layout metadata is an optimization; cache failures must not block the
      // forum home document from being displayed.
      return null;
    }
  }
}
