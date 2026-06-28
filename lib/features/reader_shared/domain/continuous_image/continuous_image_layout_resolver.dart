import 'continuous_image_models.dart';

class ContinuousImageDimensionCandidate {
  const ContinuousImageDimensionCandidate({
    required this.width,
    required this.height,
    required this.source,
  });

  final int? width;
  final int? height;
  final ContinuousImageDimensionSource source;

  ContinuousImageDimensions? get dimensions {
    final width = this.width;
    final height = this.height;
    if (width == null || height == null) {
      return null;
    }
    final dimensions = ContinuousImageDimensions(width: width, height: height);
    return dimensions.isValid ? dimensions : null;
  }
}

class ContinuousImageLayoutResolver {
  const ContinuousImageLayoutResolver();

  ContinuousImageLayoutHint resolveInitialHint({
    required ContinuousImageItem item,
    ContinuousImageDimensionCandidate? htmlDimensions,
    ContinuousImageDimensionCandidate? persistedDimensions,
    ContinuousImageDimensionCandidate? probedDimensions,
  }) {
    final knownDimensions = item.knownDimensions;
    final candidates = <ContinuousImageDimensionCandidate>[
      ?htmlDimensions,
      ?persistedDimensions,
      if (knownDimensions != null)
        ContinuousImageDimensionCandidate(
          width: knownDimensions.width,
          height: knownDimensions.height,
          source: item.effectiveKnownDimensionSource,
        ),
      ?probedDimensions,
    ];
    for (final candidate in candidates) {
      final hint = resolveFromDimensions(candidate);
      if (hint != null) {
        return hint;
      }
    }
    return fallbackHint(item);
  }

  ContinuousImageLayoutHint? resolveFromDimensions(
    ContinuousImageDimensionCandidate candidate,
  ) {
    final aspectRatio = candidate.dimensions?.aspectRatioOrNull;
    if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
      return null;
    }
    return ContinuousImageLayoutHint(
      aspectRatio: aspectRatio,
      source: candidate.source,
    );
  }

  ContinuousImageLayoutHint? resolveDecodedHint({
    required int width,
    required int height,
  }) {
    return resolveFromDimensions(
      ContinuousImageDimensionCandidate(
        width: width,
        height: height,
        source: ContinuousImageDimensionSource.decodedImage,
      ),
    );
  }

  ContinuousImageLayoutHint fallbackHint(ContinuousImageItem item) {
    final fallback = item.fallbackAspectRatio;
    return ContinuousImageLayoutHint(
      aspectRatio: fallback.isFinite && fallback > 0 ? fallback : 0.7,
      source: ContinuousImageDimensionSource.fallback,
    );
  }
}
