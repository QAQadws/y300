import 'package:flutter/foundation.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_settings.dart';
import 'package:y300/features/thread/domain/models/thread_post_segmentation_config.dart';

/// Render-configuration cache key for thread post body plans.
///
/// Replaces ad-hoc hand-written signature strings. When a new render-affecting
/// factor is added, it must be added here as a field and covered by [==] — the
/// compiler and tests then enforce correctness, preventing silent cache misses.
///
/// Fields that depend on phases not yet landed (e.g. [converterId] for
/// Phase 2, [typographyHashCode] for Phase 3) are carried as plain strings so
/// they can be substituted with proper value objects as each phase lands.
@immutable
class ThreadPostRenderCacheKey {
  const ThreadPostRenderCacheKey({
    required this.renderSettings,
    required this.displayTransformerSignature,
    required this.resourceHintResolverSignature,
    required this.segmentation,
  });

  final ThreadPostBodyRenderSettings renderSettings;

  /// Identifies the display transformer; Phase 2 will replace with a typed
  /// [TextConverter] value object once that abstraction lands.
  final String displayTransformerSignature;

  /// Identifies the resource layout hint resolver configuration; Phase 2+
  /// may evolve this further once the resolver gains full value equality.
  final String resourceHintResolverSignature;

  final ThreadPostSegmentationConfig segmentation;

  @override
  bool operator ==(Object other) {
    if (other is! ThreadPostRenderCacheKey) return false;
    return renderSettings == other.renderSettings &&
        displayTransformerSignature == other.displayTransformerSignature &&
        resourceHintResolverSignature == other.resourceHintResolverSignature &&
        segmentation == other.segmentation;
  }

  @override
  int get hashCode => Object.hash(
    renderSettings,
    displayTransformerSignature,
    resourceHintResolverSignature,
    segmentation,
  );
}
