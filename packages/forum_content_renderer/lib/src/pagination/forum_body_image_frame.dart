import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../contracts/forum_html_display_image.dart';
import '../document/forum_body_document.dart';
import '../html_rendering/forum_html_prepared_render_document.dart';

/// One immutable Host-prepared resource and its layout hint. Resolving this
/// value is synchronous and must not start transport or dimension work.
typedef ForumBodyImageResolver =
    ForumBodyImageInput? Function(
      ForumBodyIdentity identity,
      ForumBodyElement element,
    );

final class ForumBodyImageInput {
  ForumBodyImageInput({
    required this.identity,
    required this.element,
    required this.entry,
    required this.layout,
    this.isSticker = false,
  }) {
    if (element.kind != ForumBodyElementKind.image ||
        element.resource?.rawSource != entry.rawSrc ||
        entry.url.isEmpty ||
        entry.cacheKey.isEmpty ||
        entry.index < 0) {
      throw ArgumentError('Image input does not describe its source element');
    }
  }
  final ForumBodyIdentity identity;
  final ForumBodyElement element;
  final ForumHtmlReadableImageEntry entry;
  final ForumHtmlImageLayout layout;
  final bool isSticker;

  double get aspectRatio =>
      layout.aspectRatio ??
      layout.displaySize?.aspectRatio ??
      (entry.htmlWidth != null && entry.htmlHeight != null
          ? entry.htmlWidth! / entry.htmlHeight!
          : .7);

  int get retainedCodeUnits =>
      entry.url.length +
      entry.rawSrc.length +
      entry.cacheKey.length +
      (entry.alt?.length ?? 0) +
      (entry.title?.length ?? 0) +
      (entry.attachmentId?.length ?? 0);
}

/// Physical placement only. It contains no text row, glyph or source offset.
/// A tall block fits proportionally inside one page; the Host retains the
/// original resource for its image viewer. Unknown dimensions use the explicit
/// current Host hint and must reflow in a new generation when it changes.
final class ForumBodyImageFrame {
  ForumBodyImageFrame._(this.width, this.height, this.imageRect);
  factory ForumBodyImageFrame.resolve({
    required ForumBodyImageInput input,
    required double width,
    required double maxHeight,
    double? maxImageWidth,
    required TextAlign align,
    required TextDirection direction,
  }) {
    final ratio = input.aspectRatio;
    if (!width.isFinite ||
        width <= 0 ||
        !maxHeight.isFinite ||
        maxHeight <= 0 ||
        !ratio.isFinite ||
        ratio <= 0 ||
        (maxImageWidth != null &&
            (!maxImageWidth.isFinite || maxImageWidth <= 0))) {
      throw ArgumentError('Invalid image frame geometry');
    }
    final limit = math.min(width, maxImageWidth ?? width);
    final height = math.min(maxHeight, limit / ratio),
        imageWidth = math.min(limit, height * ratio);
    final factor = switch ((align, direction)) {
      (TextAlign.center, _) => .5,
      (TextAlign.right, _) ||
      (TextAlign.end, TextDirection.ltr) ||
      (TextAlign.start || TextAlign.justify, TextDirection.rtl) => 1.0,
      _ => 0.0,
    };
    return ForumBodyImageFrame._(
      width,
      height,
      Rect.fromLTWH((width - imageWidth) * factor, 0, imageWidth, height),
    );
  }
  final double width, height;
  final Rect imageRect;
  @override
  bool operator ==(Object other) =>
      other is ForumBodyImageFrame &&
      other.width == width &&
      other.height == height &&
      other.imageRect == imageRect;
  @override
  int get hashCode => Object.hash(width, height, imageRect);
}
