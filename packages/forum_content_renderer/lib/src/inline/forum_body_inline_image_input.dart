import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../contracts/forum_html_display_image.dart';
import '../document/forum_body_document.dart';
import '../html_rendering/forum_html_prepared_render_document.dart';

/// One actual IR image occurrence and its resolved inline dimensions. The
/// display description is an immutable Host value, never the Host or transport.
/// Stickers have no invented readable-image ordinal or text/source interval.
final class ForumBodyInlineImageInput {
  ForumBodyInlineImageInput({
    required ForumBodyDocument document,
    required this.element,
    required this.image,
    required this.dimensions,
    this.entry,
  }) : identity = document.identity {
    final size = dimensions.size, baseline = dimensions.baselineOffset;
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
                entry!.index < 0)) ||
        !size.width.isFinite ||
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
  final ForumBodyIdentity identity;
  final ForumBodyElement element;
  final ForumHtmlDisplayImage image;
  final PlaceholderDimensions dimensions;
  final ForumHtmlReadableImageEntry? entry;
  int get retainedCodeUnits =>
      image.sourceUrl.length +
      image.cacheKey.length +
      element.resource!.rawSource!.length +
      (element.resource!.alt?.length ?? 0) +
      (element.resource!.title?.length ?? 0);
}
