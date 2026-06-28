class TallImagePolicy {
  const TallImagePolicy({
    this.enabled = false,
    this.heightToWidthThreshold = 3,
    this.optimalHeightViewportMultiplier = 2,
  }) : assert(heightToWidthThreshold > 0),
       assert(optimalHeightViewportMultiplier > 0);

  static const disabled = TallImagePolicy();

  static const mihonLike = TallImagePolicy(
    enabled: true,
    heightToWidthThreshold: 3,
    optimalHeightViewportMultiplier: 2,
  );

  final bool enabled;
  final double heightToWidthThreshold;
  final double optimalHeightViewportMultiplier;

  bool shouldSplit({
    required int imageWidth,
    required int imageHeight,
    required double viewportMainAxisExtent,
  }) {
    if (!enabled ||
        imageWidth <= 0 ||
        imageHeight <= 0 ||
        viewportMainAxisExtent <= 0) {
      return false;
    }
    return imageHeight > imageWidth * heightToWidthThreshold &&
        calculatePartCount(
              imageHeight: imageHeight,
              optimalImageHeight: optimalImageHeightForViewport(
                viewportMainAxisExtent,
              ),
            ) >
            1;
  }

  int optimalImageHeightForViewport(double viewportMainAxisExtent) {
    if (viewportMainAxisExtent <= 0) {
      return 0;
    }
    return (viewportMainAxisExtent * optimalHeightViewportMultiplier).round();
  }

  int calculatePartCount({
    required int imageHeight,
    required int optimalImageHeight,
  }) {
    if (imageHeight <= 0 || optimalImageHeight <= 0) {
      return 0;
    }
    return ((imageHeight - 1) ~/ optimalImageHeight) + 1;
  }
}
