import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../contracts/forum_html_display_image.dart';
import '../document/forum_body_document.dart';
import '../html_rendering/forum_html_prepared_render_document.dart';
import '../style/forum_body_box_style.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';

/// Synchronous frozen-resource classification. Null retains block-image flow;
/// this port must not start transport, dimension lookup or native layout work.
typedef ForumBodyInlineImageResolver =
    ForumBodyInlineImageInput? Function(
      ForumBodyIdentity identity,
      ForumBodyElement element,
      ForumBodyResolvedStyle style,
    );

/// One frozen actual image occurrence, independent of its paragraph geometry.
/// Reflow may change dimensions while retaining this exact source association.
final class ForumBodyInlineImageSource {
  ForumBodyInlineImageSource({
    required ForumBodyDocument document,
    required this.element,
    required this.image,
    this.entry,
  }) : identity = document.identity {
    if (!identical(document.nodeAtPath(element.path), element) ||
        element.kind != ForumBodyElementKind.image ||
        element.resource?.rawSource == null ||
        image.sourceUrl.isEmpty ||
        image.cacheKey.isEmpty ||
        image.isSticker != (entry == null) ||
        (entry != null &&
            (entry!.rawSrc != element.resource!.rawSource ||
                entry!.url != image.sourceUrl ||
                entry!.cacheKey != image.cacheKey ||
                (element.resource!.readableImageIndex != null &&
                    entry!.index != element.resource!.readableImageIndex) ||
                entry!.index < 0))) {
      throw ArgumentError('Inline image source does not match its document');
    }
  }
  final ForumBodyIdentity identity;
  final ForumBodyElement element;
  final ForumHtmlDisplayImage image;
  final ForumHtmlReadableImageEntry? entry;
  int get retainedCodeUnits =>
      image.sourceUrl.length +
      image.cacheKey.length +
      element.resource!.rawSource!.length +
      (element.resource!.alt?.length ?? 0) +
      (element.resource!.title?.length ?? 0);
}

/// Geometry for one frozen source. Replaced elements resolve author lengths
/// at the actual paragraph width before they become native slots.
final class ForumBodyInlineImageInput {
  factory ForumBodyInlineImageInput({
    required ForumBodyDocument document,
    required ForumBodyElement element,
    required ForumHtmlDisplayImage image,
    required PlaceholderDimensions dimensions,
    ForumHtmlReadableImageEntry? entry,
  }) => ForumBodyInlineImageInput.fromSource(
    source: ForumBodyInlineImageSource(
      document: document,
      element: element,
      image: image,
      entry: entry,
    ),
    dimensions: dimensions,
  );

  ForumBodyInlineImageInput.fromSource({
    required ForumBodyInlineImageSource source,
    required PlaceholderDimensions dimensions,
  }) : this._(source, dimensions, false, null);

  factory ForumBodyInlineImageInput.replaced({
    required ForumBodyInlineImageSource source,
    required ForumBodyBoxStyle box,
    required Size intrinsicSize,
    required double maxHeight,
  }) {
    if (!maxHeight.isFinite || maxHeight <= 0) {
      throw ArgumentError.value(maxHeight, 'maxHeight');
    }
    final reference = source.element.resource!;
    final width = box.width ?? _htmlLength(reference.width);
    final height = box.height ?? _htmlLength(reference.height);
    final automaticWidth =
        width == null || width.unit == ForumBodyLengthUnit.auto;
    // A paged flow paragraph has no definite CSS containing-block height.
    final automaticHeight =
        height == null ||
        height.unit == ForumBodyLengthUnit.auto ||
        height.unit == ForumBodyLengthUnit.percent;
    return ForumBodyInlineImageInput._(
      source,
      _baselineSize(intrinsicSize),
      automaticWidth || automaticHeight,
      (
        width: automaticWidth ? null : width,
        height: automaticHeight ? null : height,
        minWidth: box.minWidth,
        maxWidth: box.maxWidth,
        maxHeight: maxHeight,
      ),
    );
  }

  ForumBodyInlineImageInput._(
    this.source,
    this.dimensions,
    this.usesIntrinsicSize,
    this._sizing,
  ) {
    final size = dimensions.size, baseline = dimensions.baselineOffset;
    if (!size.width.isFinite ||
        size.width <= 0 ||
        !size.height.isFinite ||
        size.height <= 0 ||
        dimensions.alignment != ui.PlaceholderAlignment.baseline ||
        dimensions.baseline != TextBaseline.alphabetic ||
        baseline == null ||
        !baseline.isFinite ||
        baseline < 0 ||
        baseline > size.height) {
      throw ArgumentError('Inline image does not match its source or geometry');
    }
  }
  final ForumBodyInlineImageSource source;
  ForumBodyIdentity get identity => source.identity;
  ForumBodyElement get element => source.element;
  ForumHtmlDisplayImage get image => source.image;
  final PlaceholderDimensions dimensions;
  final bool usesIntrinsicSize;
  final ({
    ForumBodyLength? width,
    ForumBodyLength? height,
    ForumBodyLength minWidth,
    ForumBodyLength? maxWidth,
    double maxHeight,
  })?
  _sizing;
  ForumHtmlReadableImageEntry? get entry => source.entry;
  int get retainedCodeUnits => source.retainedCodeUnits;

  /// Fit the actual containing paragraph without upscaling or applying text
  /// scale again. Baseline and aspect ratio use the same physical transform.
  ForumBodyInlineImageInput fitWidth(
    double availableWidth, {
    double? containingWidth,
  }) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      throw ArgumentError.value(availableWidth, 'availableWidth');
    }
    final sizing = _sizing;
    if (sizing != null) {
      final reference = containingWidth ?? availableWidth;
      if (!reference.isFinite || reference <= 0) {
        throw ArgumentError.value(reference, 'containingWidth');
      }
      final intrinsic = dimensions.size;
      final width = _usedPixels(sizing.width, reference);
      final height = _usedPixels(sizing.height, reference);
      final naturalWidth =
          width ??
          (height == null ? intrinsic.width : height * intrinsic.aspectRatio);
      final maxWidth =
          _usedPixels(sizing.maxWidth, reference) ?? double.infinity;
      final minWidth = _usedPixels(sizing.minWidth, reference)!;
      final usedWidth = math.max(minWidth, math.min(naturalWidth, maxWidth));
      final usedHeight = height ?? usedWidth / intrinsic.aspectRatio;
      final scale = math.min(
        1.0,
        math.min(availableWidth / usedWidth, sizing.maxHeight / usedHeight),
      );
      return ForumBodyInlineImageInput._(
        source,
        _baselineSize(Size(usedWidth * scale, usedHeight * scale)),
        usesIntrinsicSize,
        null,
      );
    }
    if (dimensions.size.width <= availableWidth) return this;
    final factor = availableWidth / dimensions.size.width;
    return ForumBodyInlineImageInput._(
      source,
      PlaceholderDimensions(
        size: Size(availableWidth, dimensions.size.height * factor),
        alignment: dimensions.alignment,
        baseline: dimensions.baseline,
        baselineOffset: dimensions.baselineOffset! * factor,
      ),
      usesIntrinsicSize,
      null,
    );
  }
}

ForumBodyLength? _htmlLength(double? value) =>
    value == null ? null : ForumBodyLength(value);

double? _usedPixels(ForumBodyLength? length, double containingWidth) =>
    switch (length?.unit) {
      null => null,
      ForumBodyLengthUnit.px => length!.value,
      ForumBodyLengthUnit.percent => containingWidth * (length!.value / 100),
      _ => throw ArgumentError('Image sizing needs computed lengths'),
    };

PlaceholderDimensions _baselineSize(Size size) => PlaceholderDimensions(
  size: size,
  alignment: ui.PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  baselineOffset: size.height,
);
