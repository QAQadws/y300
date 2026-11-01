import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';

/// Numeric geometry for one original annotation rank. Empty positions remain
/// in the list; they neither borrow a glyph handle nor reserve a gap by itself.
final class ForumBodyRubyAnnotationMetrics {
  const ForumBodyRubyAnnotationMetrics._({
    required this.side,
    required this.gap,
    required this.hasAnnotation,
    required this.fontBaseline,
    required this.bounds,
    this.offset = Offset.zero,
    this.bandTop = 0,
    this.bandBottom = 0,
  });

  final ForumBodyRubySide side;
  final double gap;
  final bool hasAnnotation;
  final double fontBaseline;

  /// Includes both actual native row bounds and glyph overhang.
  final Rect bounds;
  final Offset offset;

  /// Shared level envelope in column coordinates, independent of glyph size.
  final double bandTop;
  final double bandBottom;
  double get ascent => hasAnnotation ? fontBaseline - bounds.top : 0;
  double get descent => hasAnnotation ? bounds.bottom - fontBaseline : 0;

  ForumBodyRubyAnnotationMetrics _positioned({
    required double width,
    required double baseline,
    required double relativeBaseline,
    required double top,
    required double bottom,
  }) => ForumBodyRubyAnnotationMetrics._(
    side: side,
    gap: gap,
    hasAnnotation: hasAnnotation,
    fontBaseline: fontBaseline,
    bounds: bounds,
    offset: Offset(
      (width - bounds.width) / 2 - bounds.left,
      hasAnnotation ? baseline + relativeBaseline - fontBaseline : 0,
    ),
    bandTop: baseline + top,
    bandBottom: baseline + bottom,
  );
}

/// Actual glyph geometry shared by planning and readable ruby groups. This
/// immutable numeric value retains no native handle, content, owner or callback
/// and supplies no paint/hit/coverage proof after its borrowed inputs retire.
final class ForumBodyRubyGroupMetrics {
  ForumBodyRubyGroupMetrics._({
    required this.size,
    required this.baseline,
    required this.baseOffset,
    required this.baseFontBaseline,
    required this.baseAscent,
    required this.baseDescent,
    required List<ForumBodyRubyAnnotationMetrics> annotations,
  }) : annotations = List.unmodifiable(annotations),
       alignmentSignature = annotations.map((item) => item.side.index).join();

  static const revision = 5;
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
  }) => ForumBodyRubyGroupMetrics.measureLayers(
    cache: cache,
    baseLease: baseLease,
    annotations: [
      (content: annotation, lease: annotationLease, gap: gap, side: side),
    ],
    maxWidth: maxWidth,
  );

  /// One base layout for all annotation ranks, in inner-to-outer source order.
  /// The caller resolves each rank's side; this layer never infers CSS or
  /// concatenates independently shaped RT contents. Null leases are only for
  /// actual empty inputs, including a missing RT in an otherwise populated rank.
  factory ForumBodyRubyGroupMetrics.measureLayers({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease baseLease,
    required List<
      ({
        ForumBodyParagraphContent content,
        ForumBodyTextLease? lease,
        double gap,
        ForumBodyRubySide side,
      })
    >
    annotations,
    double maxWidth = 16384,
  }) {
    if (!cache.ownsLease(baseLease) ||
        annotations.any(
          (item) => item.lease != null && !cache.ownsLease(item.lease!),
        )) {
      throw StateError('Ruby child lease is not active in this reading owner');
    }
    validateForumBodyRubyColumnInputs(
      base: baseLease.content,
      annotations: [
        for (final item in annotations) (content: item.content, gap: item.gap),
      ],
      maxWidth: maxWidth,
    );
    final baseBounds = _textBounds(baseLease);
    final baseFontBaseline = baseLease.layout.alphabeticBaseline;
    if (!baseFontBaseline.isFinite) _invalid();
    final measured = <ForumBodyRubyAnnotationMetrics>[];
    var width = baseBounds.width;
    for (final item in annotations) {
      final lease = item.lease;
      if (item.content.projection.text.isNotEmpty != (lease != null) ||
          (lease != null && !identical(lease.content, item.content))) {
        throw const ForumBodyRubyGroupException(
          ForumBodyRubyGroupFailure.content,
        );
      }
      final bounds = lease == null ? Rect.zero : _textBounds(lease);
      final fontBaseline = lease?.layout.alphabeticBaseline ?? 0;
      if (!fontBaseline.isFinite) _invalid();
      measured.add(
        ForumBodyRubyAnnotationMetrics._(
          side: item.side,
          gap: item.gap,
          hasAnnotation: lease != null,
          fontBaseline: fontBaseline,
          bounds: bounds,
        ),
      );
      width = math.max(width, bounds.width);
    }
    if (width > maxWidth) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.overflow,
      );
    }
    final raw = ForumBodyRubyGroupMetrics._(
      size: Size(width, baseBounds.height),
      baseline: baseFontBaseline - baseBounds.top,
      baseOffset: Offset(
        (width - baseBounds.width) / 2 - baseBounds.left,
        -baseBounds.top,
      ),
      baseFontBaseline: baseFontBaseline,
      baseAscent: baseFontBaseline - baseBounds.top,
      baseDescent: baseBounds.bottom - baseFontBaseline,
      annotations: measured,
    );
    return raw._positioned(ForumBodyRubyLevelMetrics.single(raw));
  }

  final Size size;
  final double baseline;
  final Offset baseOffset;
  final double baseFontBaseline;
  final double baseAscent;
  final double baseDescent;
  final List<ForumBodyRubyAnnotationMetrics> annotations;

  /// Ordered side topology, only for separating numeric unions. Rank is the
  /// list position, so first and third over levels cannot collapse together.
  final String alignmentSignature;
  bool get hasAnnotation => annotations.any((item) => item.hasAnnotation);

  // Single-level callers remain source-compatible. A multi-level caller must
  // address the actual rank rather than silently treating the first as all RTs.
  Offset get annotationOffset => annotations.single.offset;
  double get annotationFontBaseline => annotations.single.fontBaseline;
  double get annotationAscent => annotations.single.ascent;
  double get annotationDescent => annotations.single.descent;
  double get gap => annotations.single.gap;
  ForumBodyRubySide get side => annotations.single.side;
  double get annotationHitBoundary {
    final annotation = annotations.single;
    return annotation.side == ForumBodyRubySide.over
        ? annotation.bandBottom + annotation.gap / 2
        : annotation.bandTop - annotation.gap / 2;
  }

  /// Only an actual annotation shift needs another parent layout. Padding a
  /// shorter unannotated column would not change its paint relative to baseline.
  bool needsLevelAlignment(ForumBodyRubyLevelMetrics level) {
    if (!level.contains(this)) _invalid();
    final positions = level._positions();
    for (final (index, annotation) in annotations.indexed) {
      if (annotation.hasAnnotation &&
          ((annotation.fontBaseline + annotation.offset.dy - baseline) -
                      positions[index].baseline)
                  .abs() >
              geometryTolerance) {
        return true;
      }
    }
    return false;
  }

  /// Reuses the same measured glyph baselines; no text is shaped or scaled.
  ForumBodyRubyGroupMetrics alignedTo(ForumBodyRubyLevelMetrics level) {
    if (!level.contains(this)) _invalid();
    return _positioned(level);
  }

  ForumBodyRubyGroupMetrics _positioned(ForumBodyRubyLevelMetrics level) {
    final positions = level._positions();
    var over = level.baseAscent;
    var under = level.baseDescent;
    for (final position in positions) {
      over = math.max(over, -position.top);
      under = math.max(under, position.bottom);
    }
    final height = over + under;
    if (!height.isFinite ||
        height <= 0 ||
        height > 16384 ||
        !over.isFinite ||
        over < 0 ||
        over > height) {
      _invalid();
    }
    return ForumBodyRubyGroupMetrics._(
      size: Size(size.width, height),
      baseline: over,
      baseOffset: Offset(baseOffset.dx, over - baseFontBaseline),
      baseFontBaseline: baseFontBaseline,
      baseAscent: baseAscent,
      baseDescent: baseDescent,
      annotations: [
        for (final (index, annotation) in annotations.indexed)
          annotation._positioned(
            width: size.width,
            baseline: over,
            relativeBaseline: positions[index].baseline,
            top: positions[index].top,
            bottom: positions[index].bottom,
          ),
      ],
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

  static Never _invalid() => throw const ForumBodyRubyGroupException(
    ForumBodyRubyGroupFailure.geometry,
  );
}

/// Shared numeric extents of one original annotation rank on one physical row.
final class ForumBodyRubyAnnotationLevelMetrics {
  const ForumBodyRubyAnnotationLevelMetrics._({
    required this.side,
    required this.hasAnnotation,
    required this.ascent,
    required this.descent,
    required this.gap,
  });
  factory ForumBodyRubyAnnotationLevelMetrics._single(
    ForumBodyRubyAnnotationMetrics item,
  ) => ForumBodyRubyAnnotationLevelMetrics._(
    side: item.side,
    hasAnnotation: item.hasAnnotation,
    ascent: item.ascent,
    descent: item.descent,
    gap: item.hasAnnotation ? item.gap : 0,
  );
  final ForumBodyRubySide side;
  final bool hasAnnotation;
  final double ascent;
  final double descent;
  final double gap;

  ForumBodyRubyAnnotationLevelMetrics _include(
    ForumBodyRubyAnnotationMetrics item,
  ) => ForumBodyRubyAnnotationLevelMetrics._(
    side: side,
    hasAnnotation: hasAnnotation || item.hasAnnotation,
    ascent: math.max(ascent, item.ascent),
    descent: math.max(descent, item.descent),
    gap: math.max(gap, item.hasAnnotation ? item.gap : 0),
  );
}

/// Numeric union for one ruby column stack on one physical line. It retains no
/// glyphs, input, owner or coverage proof. Unions before wrapping are only a
/// cheap alignment check, never the geometry used to publish a page.
final class ForumBodyRubyLevelMetrics {
  ForumBodyRubyLevelMetrics._({
    required this.baseAscent,
    required this.baseDescent,
    required List<ForumBodyRubyAnnotationLevelMetrics> annotations,
  }) : annotations = List.unmodifiable(annotations);

  factory ForumBodyRubyLevelMetrics.single(ForumBodyRubyGroupMetrics column) =>
      ForumBodyRubyLevelMetrics._(
        baseAscent: column.baseAscent,
        baseDescent: column.baseDescent,
        annotations: [
          for (final item in column.annotations)
            ForumBodyRubyAnnotationLevelMetrics._single(item),
        ],
      );

  final double baseAscent;
  final double baseDescent;
  final List<ForumBodyRubyAnnotationLevelMetrics> annotations;
  ForumBodyRubySide get side => annotations.single.side;
  double get annotationAscent => annotations.single.ascent;
  double get annotationDescent => annotations.single.descent;
  double get gap => annotations.single.gap;

  bool _sameRanks(ForumBodyRubyGroupMetrics column) =>
      annotations.length == column.annotations.length &&
      annotations.indexed.every(
        (entry) => entry.$2.side == column.annotations[entry.$1].side,
      );

  ForumBodyRubyLevelMetrics include(ForumBodyRubyGroupMetrics column) {
    if (!_sameRanks(column)) ForumBodyRubyGroupMetrics._invalid();
    return ForumBodyRubyLevelMetrics._(
      baseAscent: math.max(baseAscent, column.baseAscent),
      baseDescent: math.max(baseDescent, column.baseDescent),
      annotations: [
        for (final (index, item) in annotations.indexed)
          item._include(column.annotations[index]),
      ],
    );
  }

  bool contains(ForumBodyRubyGroupMetrics column) {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    return _sameRanks(column) &&
        column.baseAscent <= baseAscent + tolerance &&
        column.baseDescent <= baseDescent + tolerance &&
        annotations.indexed.every((entry) {
          final item = column.annotations[entry.$1];
          final level = entry.$2;
          return item.ascent <= level.ascent + tolerance &&
              item.descent <= level.descent + tolerance &&
              (!item.hasAnnotation ||
                  (level.hasAnnotation && item.gap <= level.gap + tolerance));
        });
  }

  List<({double baseline, double top, double bottom})> _positions() {
    var over = baseAscent;
    var under = baseDescent;
    final result = <({double baseline, double top, double bottom})>[];
    for (final item in annotations) {
      if (!item.hasAnnotation) {
        result.add((baseline: 0.0, top: 0.0, bottom: 0.0));
      } else if (item.side == ForumBodyRubySide.over) {
        final bottom = -over - item.gap;
        over += item.gap + item.ascent + item.descent;
        result.add((
          baseline: bottom - item.descent,
          top: -over,
          bottom: bottom,
        ));
      } else {
        final top = under + item.gap;
        under += item.gap + item.ascent + item.descent;
        result.add((baseline: top + item.ascent, top: top, bottom: under));
      }
    }
    return result;
  }
}
