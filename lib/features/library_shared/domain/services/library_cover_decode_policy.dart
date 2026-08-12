import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The physical pixel box requested by a concrete cover layout.
///
/// Unlike the retired bucket ladder, thumbnail targets preserve the exact
/// layout size. [original] is reserved for the full-screen viewer.
@immutable
class LibraryCoverDecodeTarget {
  const LibraryCoverDecodeTarget.thumbnail({
    required int widthPx,
    required int heightPx,
  }) : targetWidthPx = widthPx,
       targetHeightPx = heightPx,
       isOriginal = false,
       assert(widthPx > 0),
       assert(heightPx > 0);

  const LibraryCoverDecodeTarget.original()
    : targetWidthPx = null,
      targetHeightPx = null,
      isOriginal = true;

  static const int fallbackWidthPx = 256;
  static const int fallbackHeightPx = 384;

  final int? targetWidthPx;
  final int? targetHeightPx;
  final bool isOriginal;

  factory LibraryCoverDecodeTarget.fromDisplaySize({
    required Size displaySize,
    required double devicePixelRatio,
  }) {
    final validSize =
        displaySize.width.isFinite &&
        displaySize.width > 0 &&
        displaySize.height.isFinite &&
        displaySize.height > 0;
    final validDpr = devicePixelRatio.isFinite && devicePixelRatio > 0;
    if (!validSize || !validDpr) {
      return const LibraryCoverDecodeTarget.thumbnail(
        widthPx: fallbackWidthPx,
        heightPx: fallbackHeightPx,
      );
    }
    return LibraryCoverDecodeTarget.thumbnail(
      widthPx: math.max(1, (displaySize.width * devicePixelRatio).ceil()),
      heightPx: math.max(1, (displaySize.height * devicePixelRatio).ceil()),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryCoverDecodeTarget &&
        other.targetWidthPx == targetWidthPx &&
        other.targetHeightPx == targetHeightPx &&
        other.isOriginal == isOriginal;
  }

  @override
  int get hashCode => Object.hash(targetWidthPx, targetHeightPx, isOriginal);
}

abstract final class LibraryCoverDecodePolicy {
  static const int maxDecodedLongEdge = 2048;

  /// Resolves the sampled bitmap size needed to cover [target] while
  /// preserving the source aspect ratio. `null` requests the original image.
  static Size? resolveDecodedSize({
    required LibraryCoverDecodeTarget target,
    required int intrinsicWidth,
    required int intrinsicHeight,
  }) {
    if (target.isOriginal || intrinsicWidth <= 0 || intrinsicHeight <= 0) {
      return null;
    }
    final targetWidth = target.targetWidthPx!;
    final targetHeight = target.targetHeightPx!;
    var scale = math.min(
      1.0,
      math.max(targetWidth / intrinsicWidth, targetHeight / intrinsicHeight),
    );
    final decodedLongEdge = math.max(
      intrinsicWidth * scale,
      intrinsicHeight * scale,
    );
    if (decodedLongEdge > maxDecodedLongEdge) {
      scale *= maxDecodedLongEdge / decodedLongEdge;
    }
    return Size(
      math.max(1, (intrinsicWidth * scale).ceil()).toDouble(),
      math.max(1, (intrinsicHeight * scale).ceil()).toDouble(),
    );
  }
}
