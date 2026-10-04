import 'package:continuous_image_geometry/continuous_image_geometry.dart';

/// Test input independent of image sources, storage and UI policy.
final class GeometryTestItem implements ContinuousImageLayoutItem {
  const GeometryTestItem({
    required this.ownerId,
    required this.id,
    required this.index,
    this.knownWidth,
    this.knownHeight,
    this.effectiveKnownDimensionSource =
        ContinuousImageDimensionSource.persistedCache,
    this.fallbackAspectRatio = 0.7,
    this.spacingAfter = 0,
  });

  final String ownerId;
  @override
  final String id;
  @override
  final int index;
  final int? knownWidth;
  final int? knownHeight;
  @override
  final ContinuousImageDimensionSource effectiveKnownDimensionSource;
  @override
  final double fallbackAspectRatio;
  @override
  final double spacingAfter;

  @override
  ContinuousImageDimensions? get knownDimensions {
    final width = knownWidth;
    final height = knownHeight;
    if (width == null || height == null) return null;
    // Invalid candidate dimensions deliberately reach the resolver's validator.
    return ContinuousImageDimensions(width: width, height: height);
  }
}
