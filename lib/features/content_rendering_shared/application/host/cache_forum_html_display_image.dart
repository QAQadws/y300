import 'dart:ui' show Size;

import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_layout_hint_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Preserves the existing display spec and cache request behind the UI port.
final class CacheForumHtmlDisplayImage implements ForumHtmlDisplayImage {
  const CacheForumHtmlDisplayImage._({
    required this.spec,
    required this.request,
    required this.isSticker,
    required this.initialLayout,
    required this.layoutHintResolver,
  });

  final ForumImageLoadSpec spec;
  final ImageCacheRequest request;
  final ForumImageLayoutHintResolver layoutHintResolver;

  @override
  final bool isSticker;

  @override
  final ForumHtmlImageLayout initialLayout;

  @override
  String get sourceUrl => spec.sourceUrl;

  @override
  String get cacheKey => request.cacheKey;

  @override
  Object get identity => (request.cacheKey, request.sourceUrl, spec.sourceUrl);

  @override
  Size? get htmlSize => ForumImageDimensions.fromHtmlSpec(spec)?.size;

  static CacheForumHtmlDisplayImage? fromSpec(
    ForumImageLoadSpec spec, {
    required bool isSticker,
    ForumImageRequestResolver imageRequestResolver =
        const DefaultForumImageRequestResolver(),
    ForumImageLayoutHintResolver layoutHintResolver =
        const ForumImageLayoutHintResolver(),
    double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
    fallbackAspectRatioFor,
  }) {
    final request = imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) return null;
    var hint = layoutHintResolver.resolve(spec: spec);
    if (!isSticker &&
        hint.layoutMode == ForumImageLayoutMode.blockWithFallbackAspectRatio) {
      final learnedAspectRatio = fallbackAspectRatioFor?.call(spec, request);
      if (learnedAspectRatio != null &&
          learnedAspectRatio.isFinite &&
          learnedAspectRatio > 0) {
        hint = ForumImageLayoutHint(
          layoutMode: ForumImageLayoutMode.blockWithFallbackAspectRatio,
          aspectRatio: learnedAspectRatio,
        );
      }
    }
    return CacheForumHtmlDisplayImage._(
      spec: spec,
      request: request,
      isSticker: isSticker,
      initialLayout: _layout(hint),
      layoutHintResolver: layoutHintResolver,
    );
  }

  ForumHtmlImageLayout layoutForCacheDimensions(
    ForumImageDimensions dimensions,
  ) => _layout(
    layoutHintResolver.resolve(spec: spec, cacheDimensions: dimensions),
  );

  static ForumHtmlImageLayout _layout(ForumImageLayoutHint hint) =>
      ForumHtmlImageLayout(
        isFallback:
            hint.layoutMode ==
            ForumImageLayoutMode.blockWithFallbackAspectRatio,
        aspectRatio: hint.aspectRatio,
        displaySize: hint.displaySize,
      );
}
