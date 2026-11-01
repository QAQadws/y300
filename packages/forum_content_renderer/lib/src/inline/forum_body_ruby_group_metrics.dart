import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';

part 'forum_body_ruby_numeric_work.dart';
part 'forum_body_ruby_segment_metrics.dart';
part 'forum_body_ruby_segment_positioning.dart';
part 'forum_body_ruby_atom_metrics.dart';
part 'forum_body_ruby_soft_space_metrics.dart';

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
    final bounds = lease == null
        ? Rect.zero
        : ForumBodyRubyGroupMetrics._textBounds(lease);
    final baseline = lease?.layout.alphabeticBaseline ?? 0;
    if (!baseline.isFinite) ForumBodyRubyGroupMetrics._invalid();
    return ForumBodyRubyAnnotationMetrics._(
      side: side,
      gap: gap,
      hasAnnotation: lease != null,
      fontBaseline: baseline,
      bounds: bounds,
    );
  }

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
    required this.baseBandTop,
    required this.baseBandBottom,
    required this.baseFontBaseline,
    required this.baseAscent,
    required this.baseDescent,
    required List<ForumBodyRubyAnnotationMetrics> annotations,
    String? alignmentSignature,
  }) : annotations = List.unmodifiable(annotations),
       alignmentSignature =
           alignmentSignature ??
           annotations.map((item) => item.side.index).join();

  static const revision = 6;
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

/// Format-internal incremental measurement. Borrow a single child per append;
/// final positioning consumes at most maxParts ranks. No lease or cache is
/// retained here, and transferred numeric output retains no planned content.
final class ForumBodyRubyGroupMeasurement {
  ForumBodyRubyGroupMeasurement({
    required ForumBodyParagraphContent base,
    required List<
      ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
    >
    annotations,
    this.maxWidth = 16384,
    this.level,
    bool allowEmptyBase = false,
  }) : _baseContent = base,
       _inputs = List.of(annotations) {
    validateForumBodyRubyColumnInputs(
      base: base,
      annotations: [
        for (final item in _inputs) (content: item.content, gap: item.gap),
      ],
      maxWidth: maxWidth,
      allowEmptyBase: allowEmptyBase,
    );
    if (level != null && level!.annotations.length != _inputs.length) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  ForumBodyParagraphContent? _baseContent;
  List<
    ({ForumBodyParagraphContent content, double gap, ForumBodyRubySide side})
  >
  _inputs;
  final double maxWidth;
  final ForumBodyRubyLevelMetrics? level;
  Rect? _baseBounds;
  double _baseFontBaseline = 0;
  double _baseAscent = 0;
  double _baseDescent = 0;
  double _width = 0;
  _RubyStack? _stack;
  final _raw = <ForumBodyRubyAnnotationMetrics>[];
  final _positions = <({double baseline, double top, double bottom})>[];
  final _positioned = <ForumBodyRubyAnnotationMetrics>[];
  final _signature = StringBuffer();
  ForumBodyRubyGroupMetrics? _result;
  bool _closed = false;
  int get measuredAnnotations => _raw.length;
  int get positionedAnnotations => _positioned.length;
  bool get isMeasured => _baseBounds != null && _raw.length == _inputs.length;
  bool get isReady => _result != null;

  void addBase(ForumBodyParagraphCache cache, ForumBodyTextLease lease) {
    _ensureActive();
    if (_baseBounds != null) throw StateError('Ruby base was already measured');
    if (!cache.ownsLease(lease)) throw StateError('Ruby base owner is retired');
    if (!identical(lease.content, _baseContent)) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    final bounds = ForumBodyRubyGroupMetrics._textBounds(lease);
    final baseline = lease.layout.alphabeticBaseline;
    if (!baseline.isFinite) ForumBodyRubyGroupMetrics._invalid();
    _baseBounds = bounds;
    _baseFontBaseline = baseline;
    _baseAscent = baseline - bounds.top;
    _baseDescent = bounds.bottom - baseline;
    _width = bounds.width;
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    if (level != null &&
        (_baseAscent > level!.baseAscent + tolerance ||
            _baseDescent > level!.baseDescent + tolerance)) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    _stack = _RubyStack(
      level?.baseAscent ?? _baseAscent,
      level?.baseDescent ?? _baseDescent,
    );
  }

  void addAnnotation(ForumBodyParagraphCache cache, ForumBodyTextLease? lease) {
    _ensureActive();
    if (_baseBounds == null || measuredAnnotations >= _inputs.length) {
      throw StateError('Ruby annotation is out of order');
    }
    final item = _inputs[measuredAnnotations];
    if (lease != null && !cache.ownsLease(lease)) {
      throw StateError('Ruby annotation owner is retired');
    }
    if (item.content.projection.text.isNotEmpty != (lease != null) ||
        (lease != null && !identical(lease.content, item.content))) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    final raw = ForumBodyRubyAnnotationMetrics.measure(
      cache: cache,
      lease: lease,
      side: item.side,
      gap: item.gap,
    );
    final target =
        level?.annotations[measuredAnnotations] ??
        ForumBodyRubyAnnotationLevelMetrics._single(raw);
    if (!target._contains(raw)) ForumBodyRubyGroupMetrics._invalid();
    _raw.add(raw);
    _positions.add(_stack!.append(target));
    _signature.write(item.side.index);
    _width = math.max(_width, raw.bounds.width);
  }

  int advance({required int maxParts}) {
    _ensureActive();
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (!isMeasured) throw StateError('Ruby glyph measurement is incomplete');
    final over = _stack!.over;
    final height = over + _stack!.under;
    if (_width > maxWidth) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.overflow,
      );
    }
    if (!height.isFinite ||
        height <= 0 ||
        height > 16384 ||
        !over.isFinite ||
        over < 0 ||
        over > height) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    var parts = 0;
    while (_positioned.length < _raw.length && parts < maxParts) {
      final index = _positioned.length;
      final position = _positions[index];
      _positioned.add(
        _raw[index]._positioned(
          width: _width,
          baseline: over,
          relativeBaseline: position.baseline,
          top: position.top,
          bottom: position.bottom,
        ),
      );
      parts++;
    }
    if (_positioned.length == _raw.length && _result == null) {
      _result = ForumBodyRubyGroupMetrics._(
        size: Size(_width, height),
        baseline: over,
        baseOffset: Offset(
          (_width - _baseBounds!.width) / 2 - _baseBounds!.left,
          over - _baseFontBaseline,
        ),
        baseBandTop: over - (level?.baseAscent ?? _baseAscent),
        baseBandBottom: over + (level?.baseDescent ?? _baseDescent),
        baseFontBaseline: _baseFontBaseline,
        baseAscent: _baseAscent,
        baseDescent: _baseDescent,
        annotations: _positioned,
        alignmentSignature: _signature.toString(),
      );
    }
    return parts;
  }

  ForumBodyRubyGroupMetrics takeMetrics() {
    _ensureActive();
    if (!isReady) throw StateError('Ruby positions are incomplete');
    final result = _result!;
    close();
    return result;
  }

  void _ensureActive() {
    if (_closed) throw StateError('Ruby measurement is retired');
  }

  void close() {
    _closed = true;
    _baseContent = null;
    _inputs = const [];
    _result = null;
    _raw.clear();
    _positions.clear();
    _positioned.clear();
    _signature.clear();
  }
}

final class _RubyStack {
  _RubyStack(this.over, this.under);
  double over;
  double under;
  ({double baseline, double top, double bottom}) append(
    ForumBodyRubyAnnotationLevelMetrics item,
  ) {
    if (!item.hasAnnotation) return (baseline: 0.0, top: 0.0, bottom: 0.0);
    if (item.side == ForumBodyRubySide.over) {
      final bottom = -over - item.gap;
      over += item.gap + item.ascent + item.descent;
      return (baseline: bottom - item.descent, top: -over, bottom: bottom);
    }
    final top = under + item.gap;
    under += item.gap + item.ascent + item.descent;
    return (baseline: top + item.ascent, top: top, bottom: under);
  }
}
