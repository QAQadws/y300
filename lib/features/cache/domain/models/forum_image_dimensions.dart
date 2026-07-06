import 'dart:ui';

import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';

enum ForumImageDimensionSource {
  htmlAttribute,
  cacheMetadata,
  decodedImage,
  fixedContainer,
}

class ForumImageDimensions {
  const ForumImageDimensions({
    required this.width,
    required this.height,
    required this.source,
    this.recordedAt,
  });

  final double width;
  final double height;
  final ForumImageDimensionSource source;
  final DateTime? recordedAt;

  double get aspectRatio => width / height;

  Size get size => Size(width, height);

  bool get isValid {
    return width.isFinite && height.isFinite && width > 0 && height > 0;
  }

  static ForumImageDimensions? fromHtmlSpec(ForumImageLoadSpec spec) {
    return fromValues(
      width: spec.htmlWidth,
      height: spec.htmlHeight,
      source: ForumImageDimensionSource.htmlAttribute,
    );
  }

  static ForumImageDimensions? fromCacheMetadata({
    required int? width,
    required int? height,
    DateTime? recordedAt,
  }) {
    return fromValues(
      width: width?.toDouble(),
      height: height?.toDouble(),
      source: ForumImageDimensionSource.cacheMetadata,
      recordedAt: recordedAt,
    );
  }

  static ForumImageDimensions? fromValues({
    required double? width,
    required double? height,
    required ForumImageDimensionSource source,
    DateTime? recordedAt,
  }) {
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return ForumImageDimensions(
      width: width,
      height: height,
      source: source,
      recordedAt: recordedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ForumImageDimensions &&
        other.width == width &&
        other.height == height &&
        other.source == source &&
        other.recordedAt == recordedAt;
  }

  @override
  int get hashCode => Object.hash(width, height, source, recordedAt);
}

class ForumImageLayoutHint {
  const ForumImageLayoutHint({
    required this.layoutMode,
    this.dimensionSource,
    this.aspectRatio,
    this.displaySize,
  });

  final ForumImageLayoutMode layoutMode;
  final ForumImageDimensionSource? dimensionSource;
  final double? aspectRatio;
  final Size? displaySize;

  bool get hasDisplaySize => displaySize != null;

  @override
  bool operator ==(Object other) {
    return other is ForumImageLayoutHint &&
        other.layoutMode == layoutMode &&
        other.dimensionSource == dimensionSource &&
        other.aspectRatio == aspectRatio &&
        other.displaySize == displaySize;
  }

  @override
  int get hashCode {
    return Object.hash(layoutMode, dimensionSource, aspectRatio, displaySize);
  }
}
