import 'package:flutter/foundation.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_segmentation_config.dart';

/// Render-configuration cache key for thread post body plans.
///
/// Replaces ad-hoc hand-written signature strings. When a new render-affecting
/// factor is added, it must be added here as a field and covered by [==] — the
/// compiler and tests then enforce correctness, preventing silent cache misses.
@immutable
class ThreadPostRenderCacheKey {
  const ThreadPostRenderCacheKey({
    required this.renderSettings,
    required this.displayTransformerSignature,
    required this.resourceHintResolverSignature,
    required this.segmentation,
    this.converterId = 'conv:none',
  });

  final ThreadPostBodyRenderSettings renderSettings;
  final String displayTransformerSignature;
  final String resourceHintResolverSignature;
  final ThreadPostSegmentationConfig segmentation;

  /// Identifies the [TextConverter] applied to the HTML before planning.
  /// Defaults to [IdentityTextConverter.id] ('conv:none') when no conversion
  /// is active. Changing this value invalidates the render plan cache.
  final String converterId;

  @override
  bool operator ==(Object other) {
    if (other is! ThreadPostRenderCacheKey) return false;
    return renderSettings == other.renderSettings &&
        displayTransformerSignature == other.displayTransformerSignature &&
        resourceHintResolverSignature == other.resourceHintResolverSignature &&
        segmentation == other.segmentation &&
        converterId == other.converterId;
  }

  @override
  int get hashCode => Object.hash(
    renderSettings,
    displayTransformerSignature,
    resourceHintResolverSignature,
    segmentation,
    converterId,
  );
}
