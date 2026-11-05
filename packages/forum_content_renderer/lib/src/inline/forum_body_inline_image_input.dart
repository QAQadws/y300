import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../contracts/forum_html_display_image.dart';
import '../document/forum_body_document.dart';
import '../html_rendering/forum_html_prepared_render_document.dart';
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

/// Resolved geometry for one frozen source. Stickers never acquire a readable
/// image ordinal or text/source interval. Dimensions are already scaled.
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
    required this.source,
    required this.dimensions,
  }) {
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
  ForumHtmlReadableImageEntry? get entry => source.entry;
  int get retainedCodeUnits => source.retainedCodeUnits;

  /// Fit the actual containing paragraph without upscaling or applying text
  /// scale again. Baseline and aspect ratio use the same physical transform.
  ForumBodyInlineImageInput fitWidth(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      throw ArgumentError.value(availableWidth, 'availableWidth');
    }
    if (dimensions.size.width <= availableWidth) return this;
    final factor = availableWidth / dimensions.size.width;
    return ForumBodyInlineImageInput.fromSource(
      source: source,
      dimensions: PlaceholderDimensions(
        size: Size(availableWidth, dimensions.size.height * factor),
        alignment: dimensions.alignment,
        baseline: dimensions.baseline,
        baselineOffset: dimensions.baselineOffset! * factor,
      ),
    );
  }
}
