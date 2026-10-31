import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_group_contract.dart';

/// Actual glyph geometry shared by planning and readable ruby groups. This
/// immutable numeric value retains no native handle, content, owner or callback
/// and supplies no paint/hit/coverage proof after its borrowed inputs retire.
final class ForumBodyRubyGroupMetrics {
  const ForumBodyRubyGroupMetrics._({
    required this.size,
    required this.baseline,
    required this.baseOffset,
    required this.annotationOffset,
    required this.hasAnnotation,
    required this.annotationHitBoundary,
  });

  static const revision = 2;

  /// Borrows current same-owner glyph leases. Does not shape, prepare pictures,
  /// transfer ownership or release the caller's handles, including on failure.
  factory ForumBodyRubyGroupMetrics.measure({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease baseLease,
    required ForumBodyParagraphContent annotation,
    ForumBodyTextLease? annotationLease,
    double gap = 0,
    double maxWidth = 16384,
  }) {
    if (!cache.ownsLease(baseLease) ||
        (annotationLease != null && !cache.ownsLease(annotationLease))) {
      throw StateError('Ruby child lease is not active in this reading owner');
    }
    validateForumBodyRubyGroupInputs(
      base: baseLease.content,
      annotation: annotation,
      gap: gap,
      maxWidth: maxWidth,
    );
    if (annotation.projection.text.isNotEmpty != (annotationLease != null) ||
        (annotationLease != null &&
            !identical(annotationLease.content, annotation))) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    final baseBounds = _textBounds(baseLease);
    final annotationBounds = annotationLease == null
        ? Rect.zero
        : _textBounds(annotationLease);
    final width = math.max(baseBounds.width, annotationBounds.width);
    final baseTop = annotationLease == null
        ? 0.0
        : annotationBounds.height + gap;
    final baseOffset = Offset(
      (width - baseBounds.width) / 2 - baseBounds.left,
      baseTop - baseBounds.top,
    );
    final height = baseTop + baseBounds.height;
    final baseline = baseOffset.dy + baseLease.layout.alphabeticBaseline;
    if (width > maxWidth) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.overflow,
      );
    }
    if (!height.isFinite ||
        height <= 0 ||
        height > 16384 ||
        !baseline.isFinite ||
        baseline < 0 ||
        baseline > height) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
    return ForumBodyRubyGroupMetrics._(
      size: Size(width, height),
      baseline: baseline,
      baseOffset: baseOffset,
      annotationOffset: Offset(
        (width - annotationBounds.width) / 2 - annotationBounds.left,
        -annotationBounds.top,
      ),
      hasAnnotation: annotationLease != null,
      annotationHitBoundary: annotationBounds.height + gap / 2,
    );
  }

  final Size size;
  final double baseline;
  final Offset baseOffset;
  final Offset annotationOffset;
  final bool hasAnnotation;
  final double annotationHitBoundary;

  PlaceholderDimensions get placeholderDimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );

  static Rect _textBounds(ForumBodyTextLease lease) {
    final layout = lease.layout;
    var bounds = Rect.fromLTWH(0, 0, layout.width, layout.height);
    // Author line-height can be smaller than actual fallback/large-run font
    // boxes. Use this same native layout's bounds, never another font shape.
    for (final box in layout.selectionBoxes(
      0,
      lease.content.projection.text.length,
    )) {
      bounds = bounds.expandToInclude(box.toRect());
    }
    return bounds;
  }
}
