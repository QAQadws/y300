import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
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
    required this.baseFontBaseline,
    required this.annotationFontBaseline,
    required this.baseAscent,
    required this.baseDescent,
    required this.annotationAscent,
    required this.annotationDescent,
    required this.gap,
    required this.side,
  });

  static const revision = 4;
  static const geometryTolerance = 1e-4;

  /// Borrows current same-owner glyph leases. Does not shape, prepare pictures,
  /// transfer ownership or release the caller's handles, including on failure.
  factory ForumBodyRubyGroupMetrics.measure({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease baseLease,
    required ForumBodyParagraphContent annotation,
    ForumBodyTextLease? annotationLease,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
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
    final baseFontBaseline = baseLease.layout.alphabeticBaseline;
    final annotationFontBaseline =
        annotationLease?.layout.alphabeticBaseline ?? 0;
    final annotationBounds = annotationLease == null
        ? Rect.zero
        : _textBounds(annotationLease);
    final width = math.max(baseBounds.width, annotationBounds.width);
    final baseTop = annotationLease == null || side == ForumBodyRubySide.under
        ? 0.0
        : annotationBounds.height + gap;
    final annotationTop =
        annotationLease != null && side == ForumBodyRubySide.under
        ? baseBounds.height + gap
        : 0.0;
    final baseOffset = Offset(
      (width - baseBounds.width) / 2 - baseBounds.left,
      baseTop - baseBounds.top,
    );
    final height =
        baseBounds.height +
        (annotationLease == null ? 0 : annotationBounds.height + gap);
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
    if (!baseFontBaseline.isFinite || !annotationFontBaseline.isFinite) {
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
        annotationTop - annotationBounds.top,
      ),
      hasAnnotation: annotationLease != null,
      annotationHitBoundary:
          (side == ForumBodyRubySide.over
              ? annotationBounds.height
              : baseBounds.height) +
          gap / 2,
      baseFontBaseline: baseFontBaseline,
      annotationFontBaseline: annotationFontBaseline,
      baseAscent: baseFontBaseline - baseBounds.top,
      baseDescent: baseBounds.bottom - baseFontBaseline,
      annotationAscent: annotationLease == null
          ? 0
          : annotationFontBaseline - annotationBounds.top,
      annotationDescent: annotationLease == null
          ? 0
          : annotationBounds.bottom - annotationFontBaseline,
      gap: gap,
      side: side,
    );
  }

  final Size size;
  final double baseline;
  final Offset baseOffset;
  final Offset annotationOffset;
  final bool hasAnnotation;
  final double annotationHitBoundary;
  final double baseFontBaseline;
  final double annotationFontBaseline;
  final double baseAscent;
  final double baseDescent;
  final double annotationAscent;
  final double annotationDescent;
  final double gap;
  final ForumBodyRubySide side;

  /// Only an actual annotation shift needs another parent layout. Padding a
  /// shorter unannotated column would not change its paint relative to baseline.
  bool needsLevelAlignment(ForumBodyRubyLevelMetrics level) =>
      hasAnnotation &&
      ((annotationFontBaseline + annotationOffset.dy - baseline) -
                  (side == ForumBodyRubySide.over
                      ? -level.baseAscent - level.gap - level.annotationDescent
                      : level.baseDescent + level.gap + level.annotationAscent))
              .abs() >
          geometryTolerance;

  /// Reuses the same measured glyph baselines; no text is shaped or scaled.
  ForumBodyRubyGroupMetrics alignedTo(ForumBodyRubyLevelMetrics level) {
    if (!level.contains(this)) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
    final annotationHeight = level.annotationAscent + level.annotationDescent;
    final over = side == ForumBodyRubySide.over;
    final baseline =
        level.baseAscent + (over ? annotationHeight + level.gap : 0);
    final height =
        baseline +
        level.baseDescent +
        (over ? 0 : annotationHeight + level.gap);
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
      size: Size(size.width, height),
      baseline: baseline,
      baseOffset: Offset(baseOffset.dx, baseline - baseFontBaseline),
      annotationOffset: hasAnnotation
          ? Offset(
              annotationOffset.dx,
              (over ? 0 : baseline + level.baseDescent + level.gap) +
                  level.annotationAscent -
                  annotationFontBaseline,
            )
          : Offset.zero,
      hasAnnotation: hasAnnotation,
      annotationHitBoundary:
          (over ? annotationHeight : level.baseAscent + level.baseDescent) +
          level.gap / 2,
      baseFontBaseline: baseFontBaseline,
      annotationFontBaseline: annotationFontBaseline,
      baseAscent: baseAscent,
      baseDescent: baseDescent,
      annotationAscent: annotationAscent,
      annotationDescent: annotationDescent,
      gap: gap,
      side: side,
    );
  }

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

/// Numeric union for one annotation level on one physical line. It retains no
/// glyphs, input, owner or coverage proof. Unions before wrapping are only a
/// cheap alignment check, never the geometry used to publish a page.
final class ForumBodyRubyLevelMetrics {
  const ForumBodyRubyLevelMetrics._({
    required this.side,
    this.baseAscent = 0,
    this.baseDescent = 0,
    this.annotationAscent = 0,
    this.annotationDescent = 0,
    this.gap = 0,
  });

  factory ForumBodyRubyLevelMetrics.single(ForumBodyRubyGroupMetrics column) =>
      ForumBodyRubyLevelMetrics._(side: column.side).include(column);

  final ForumBodyRubySide side;

  final double baseAscent;
  final double baseDescent;
  final double annotationAscent;
  final double annotationDescent;
  final double gap;

  ForumBodyRubyLevelMetrics include(ForumBodyRubyGroupMetrics column) {
    if (side != column.side) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
    return ForumBodyRubyLevelMetrics._(
      side: side,
      baseAscent: math.max(baseAscent, column.baseAscent),
      baseDescent: math.max(baseDescent, column.baseDescent),
      annotationAscent: math.max(annotationAscent, column.annotationAscent),
      annotationDescent: math.max(annotationDescent, column.annotationDescent),
      gap: math.max(gap, column.hasAnnotation ? column.gap : 0),
    );
  }

  bool contains(ForumBodyRubyGroupMetrics column) {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    return side == column.side &&
        column.baseAscent <= baseAscent + tolerance &&
        column.baseDescent <= baseDescent + tolerance &&
        column.annotationAscent <= annotationAscent + tolerance &&
        column.annotationDescent <= annotationDescent + tolerance &&
        (!column.hasAnnotation || column.gap <= gap + tolerance);
  }
}
