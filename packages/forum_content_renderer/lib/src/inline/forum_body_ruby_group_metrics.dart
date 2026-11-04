import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_layout.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_band_stack.dart';

part 'forum_body_ruby_numeric_work.dart';
part 'forum_body_ruby_segment_metrics.dart';
part 'forum_body_ruby_segment_positioning.dart';
part 'forum_body_ruby_atom_metrics.dart';
part 'forum_body_ruby_soft_space_metrics.dart';
part 'forum_body_ruby_group_measurement.dart';
part 'forum_body_ruby_group_geometry.dart';

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
    this.bandBaseline = 0,
  });

  /// Borrows one actual native member. This value owns no glyph lease and is
  /// shared by column measurement and annotation spans, not another shaper.
  factory ForumBodyRubyAnnotationMetrics.measure({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease? lease,
    required ForumBodyRubySide side,
    double gap = 0,
  }) {
    if (!gap.isFinite || gap < 0 || gap > 16384) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    if (lease != null && !cache.ownsLease(lease)) {
      throw StateError('Ruby annotation owner is retired');
    }
    if (lease != null && lease.content.projection.text.isEmpty) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    return ForumBodyRubyAnnotationMetrics._fromGeometry(
      child: lease == null
          ? null
          : ForumBodyRubyChildMetrics(
              bounds: ForumBodyRubyGroupMetrics._textBounds(lease),
              alphabeticBaseline: lease.layout.alphabeticBaseline,
            ),
      side: side,
      gap: gap,
    );
  }

  /// Numeric child input may describe a complete nested inline box. It does
  /// not assert ownership, source association or prepared paint readiness.
  factory ForumBodyRubyAnnotationMetrics._fromGeometry({
    required ForumBodyRubyChildMetrics? child,
    required ForumBodyRubySide side,
    double gap = 0,
  }) {
    if (!gap.isFinite || gap < 0 || gap > 16384) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    return ForumBodyRubyAnnotationMetrics._(
      side: side,
      gap: gap,
      hasAnnotation: child != null,
      fontBaseline: child?.alphabeticBaseline ?? 0,
      bounds: child?.bounds ?? Rect.zero,
    );
  }

  /// A complete measured child box, including nested native parents. Geometry
  /// alone does not grant ownership, source association or paint readiness.
  factory ForumBodyRubyAnnotationMetrics.fromChild({
    required ForumBodyRubyChildMetrics? child,
    required ForumBodyRubySide side,
    double gap = 0,
  }) => ForumBodyRubyAnnotationMetrics._fromGeometry(
    child: child,
    side: side,
    gap: gap,
  );

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

  /// The allocated row baseline, including a shared row with no local glyph.
  /// Unlike [fontBaseline], this is already in positioned column coordinates.
  final double bandBaseline;
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
    bandBaseline: baseline + relativeBaseline,
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
    required this.baseFontBounds,
    required this.baseBandTop,
    required this.baseBandBottom,
    required this.baseFontBaseline,
    required this.baseAscent,
    required this.baseDescent,
    required List<ForumBodyRubyAnnotationMetrics> annotations,
    String? alignmentSignature,
    Object? measuredIdentity,
  }) : annotations = List.unmodifiable(annotations),
       _measuredIdentity = measuredIdentity ?? Object(),
       alignmentSignature =
           alignmentSignature ??
           annotations.map((item) => item.side.index).join();

  static const revision = 6;
  static const geometryTolerance = 1e-4;
  final Object _measuredIdentity;

  /// Only vertical alignment of this actual measurement preserves this token.
  /// Equal geometry from another measurement does not bind the original tree;
  /// lineage itself still grants no native ownership or visible source proof.
  bool hasSameMeasuredInput(ForumBodyRubyGroupMetrics other) =>
      identical(_measuredIdentity, other._measuredIdentity);

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
    final measurement = ForumBodyRubyGroupMeasurement(
      base: baseLease.content,
      annotations: [
        for (final item in annotations)
          (content: item.content, gap: item.gap, side: item.side),
      ],
      maxWidth: maxWidth,
    );
    try {
      measurement.addBase(cache, baseLease);
      for (final item in annotations) {
        measurement.addAnnotation(cache, item.lease);
      }
      while (!measurement.isReady) {
        measurement.advance(maxParts: 32);
      }
      return measurement.takeMetrics();
    } finally {
      measurement.close();
    }
  }
  final Size size;
  final double baseline;
  final Offset baseOffset;

  /// The original measured child, before row alignment and annotation stacks.
  final Rect baseFontBounds;

  /// Allocated row envelope used to partition hits between base and layers.
  /// A smaller base's own glyph bounds must not move a shared level boundary.
  final double baseBandTop;
  final double baseBandBottom;
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
    final work = ForumBodyRubyColumnAlignment(column: this, level: level);
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return work.hasChanges;
  }

  /// Reuses the same measured glyph baselines; no text is shaped or scaled.
  ForumBodyRubyGroupMetrics alignedTo(ForumBodyRubyLevelMetrics level) {
    final work = ForumBodyRubyColumnAlignment(
      column: this,
      level: level,
      prepareResult: true,
    );
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return work.result;
  }

  PlaceholderDimensions get placeholderDimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );

  static Rect _textBounds(ForumBodyTextLease lease) {
    return forumBodyTextLayoutBounds(lease.layout);
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
  ) => _includeValues(item.hasAnnotation, item.ascent, item.descent, item.gap);

  ForumBodyRubyAnnotationLevelMetrics _includeLevel(
    ForumBodyRubyAnnotationLevelMetrics item,
  ) => _includeValues(item.hasAnnotation, item.ascent, item.descent, item.gap);

  ForumBodyRubyAnnotationLevelMetrics _includeValues(
    bool present,
    double otherAscent,
    double otherDescent,
    double otherGap,
  ) => ForumBodyRubyAnnotationLevelMetrics._(
    side: side,
    hasAnnotation: hasAnnotation || present,
    ascent: math.max(ascent, otherAscent),
    descent: math.max(descent, otherDescent),
    gap: math.max(gap, present ? otherGap : 0),
  );

  bool _contains(ForumBodyRubyAnnotationMetrics item) =>
      side == item.side &&
      _containsValues(item.hasAnnotation, item.ascent, item.descent, item.gap);

  bool _containsLevel(ForumBodyRubyAnnotationLevelMetrics item) =>
      side == item.side &&
      _containsValues(item.hasAnnotation, item.ascent, item.descent, item.gap);

  bool _containsValues(
    bool present,
    double otherAscent,
    double otherDescent,
    double otherGap,
  ) {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    return otherAscent <= ascent + tolerance &&
        otherDescent <= descent + tolerance &&
        (!present || (hasAnnotation && otherGap <= gap + tolerance));
  }
}

/// Numeric union for one ruby column stack on one physical line. It retains no
/// glyphs, input, owner or coverage proof. Unions before wrapping are only a
/// cheap alignment check, never the geometry used to publish a page.
final class ForumBodyRubyLevelMetrics {
  // Numeric workers seal this private buffer after their final rank merge.
  ForumBodyRubyLevelMetrics._owned({
    required this.baseAscent,
    required this.baseDescent,
    required List<ForumBodyRubyAnnotationLevelMetrics> annotations,
  }) : annotations = UnmodifiableListView(annotations);

  ForumBodyRubyLevelMetrics._({
    required this.baseAscent,
    required this.baseDescent,
    required List<ForumBodyRubyAnnotationLevelMetrics> annotations,
  }) : annotations = List.unmodifiable(annotations);

  factory ForumBodyRubyLevelMetrics.single(ForumBodyRubyGroupMetrics column) {
    final union = ForumBodyRubyLevelUnion();
    final work = union.merge(column);
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return union.value;
  }

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
    final union = ForumBodyRubyLevelUnion.fromLevel(this);
    final work = union.merge(column);
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return union.value;
  }

  bool contains(ForumBodyRubyGroupMetrics column) {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    return _sameRanks(column) &&
        column.baseAscent <= baseAscent + tolerance &&
        column.baseDescent <= baseDescent + tolerance &&
        annotations.indexed.every(
          (entry) => entry.$2._contains(column.annotations[entry.$1]),
        );
  }
}
