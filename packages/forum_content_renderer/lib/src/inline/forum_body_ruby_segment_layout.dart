import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_group_layout.dart';
import 'forum_body_ruby_group_metrics.dart';

part 'forum_body_ruby_segment_assembly.dart';

final class ForumBodyRubySegmentHit {
  const ForumBodyRubySegmentHit._({
    this.columnIndex,
    this.columnHit,
    this.spanIndex,
    this.gapIndex,
    this.annotationGapIndex,
    required this.position,
  });
  final int? columnIndex;
  final ForumBodyRubyHit? columnHit;
  final int? spanIndex;
  final int? gapIndex;
  final int? annotationGapIndex;
  final HtmlProjectedSourcePosition position;
}

typedef ForumBodyRubySegmentAnnotation = ({
  ForumBodyParagraphContent content,
  ForumBodyTextLease? lease,
});

/// Borrowed immutable member vectors. This snapshot neither proves readability
/// nor extends ownership; consumers still verify the actual cache and lifetime.
typedef ForumBodyRubySegmentMemberSnapshot = ({
  List<ForumBodyRubyGroupLayout> columns,
  List<ForumBodyRubySegmentAnnotation> spans,
  List<ForumBodyRubyGroupLayout> gaps,
  List<ForumBodyRubySegmentAnnotation> annotationGaps,
});

/// An unbroken span component, consuming already-prepared column groups and
/// exactly one lease for each original gap and nonempty spanning annotation. The
/// existing reading cache owns all glyphs; this port adds no cache or shaper.
final class ForumBodyRubySegmentLayout {
  ForumBodyRubySegmentLayout._(
    this._columns,
    this._spans,
    this.metrics,
    this._spanRanks,
    this._gaps,
    this._annotationGaps,
    this._annotationGapRanks,
  );

  /// Consumes ONLY these supplied handles on both success and failure. The
  /// numeric result cannot replace actual owner/content/paint/geometry checks.
  factory ForumBodyRubySegmentLayout.adopt({
    required ForumBodyParagraphCache cache,
    required List<ForumBodyRubyGroupLayout> columns,
    required List<ForumBodyRubySegmentAnnotation> spans,
    required ForumBodyRubySegmentMetrics metrics,
    List<ForumBodyRubyGroupLayout> gaps = const [],
    List<ForumBodyRubySegmentAnnotation> annotationGaps = const [],
  }) {
    final inputs = List.of(columns);
    final annotations = List.of(spans);
    final gapInputs = List.of(gaps);
    final annotationGapInputs = List.of(annotationGaps);
    ForumBodyRubySegmentAssembly? assembly;
    try {
      assembly = ForumBodyRubySegmentAssembly(
        cache: cache,
        metrics: metrics,
        columns: [
          for (final column in inputs)
            (
              base: column.inspectMembers().base.content,
              annotations: [
                for (final item in column.inspectMembers().annotations)
                  item.content,
              ],
            ),
        ],
        spans: [for (final item in annotations) item.content],
        annotationGaps: [for (final gap in annotationGapInputs) gap.content],
        gaps: [
          for (final gap in gapInputs)
            (
              base: gap.inspectMembers().base.content,
              annotations: [
                for (final a in gap.inspectMembers().annotations) a.content,
              ],
            ),
        ],
      );
      for (final column in inputs) {
        assembly.addColumn(column);
        while (assembly.hasPendingMember) {
          assembly.advance(maxParts: 32);
        }
      }
      for (final gap in gapInputs) {
        assembly.addGap(gap);
        while (assembly.hasPendingMember) {
          assembly.advance(maxParts: 32);
        }
      }
      for (final item in annotations) {
        assembly.addSpan(item);
        while (assembly.hasPendingMember) {
          assembly.advance(maxParts: 32);
        }
      }
      for (final gap in annotationGapInputs) {
        assembly.addAnnotationGap(gap);
        while (assembly.hasPendingMember) {
          assembly.advance(maxParts: 32);
        }
      }
      while (!assembly.isReady) {
        assembly.advance(maxParts: 32);
      }
      return assembly.takeLayout();
    } catch (_) {
      for (final column in inputs) {
        column.close();
      }
      for (final gap in gapInputs) {
        gap.close();
      }
      for (final item in annotations) {
        item.lease?.release();
      }
      for (final gap in annotationGapInputs) {
        gap.lease?.release();
      }
      rethrow;
    } finally {
      assembly?.close();
    }
  }

  List<ForumBodyRubyGroupLayout> _columns;
  List<ForumBodyRubyGroupLayout> _gaps;
  List<ForumBodyRubySegmentAnnotation> _spans;
  List<ForumBodyRubySegmentAnnotation> _annotationGaps;
  final Map<int, List<int>> _annotationGapRanks;
  final Map<int, List<int>> _spanRanks;
  final ForumBodyRubySegmentMetrics metrics;
  late final ForumBodyRubySegmentMemberSnapshot _members = (
    columns: UnmodifiableListView(_columns),
    spans: UnmodifiableListView(_spans),
    gaps: UnmodifiableListView(_gaps),
    annotationGaps: UnmodifiableListView(_annotationGaps),
  );
  ForumBodyRubySegmentMemberSnapshot inspectMembers() => _members;
  bool _closed = false;
  Size get size => metrics.size;
  double get baseline => metrics.baseline;
  bool get isActive =>
      !_closed &&
      _columns.every((column) => column.isActive) &&
      _gaps.every((gap) => gap.isActive) &&
      _annotationGaps.every(
        (gap) =>
            gap.lease != null &&
            gap.lease!.isActive &&
            gap.lease!.layout.isPaintPrepared,
      ) &&
      _spans.every(
        (item) =>
            item.lease == null ||
            (item.lease!.isActive && item.lease!.layout.isPaintPrepared),
      );
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive &&
      _columns.every((column) => column.isOwnedBy(cache)) &&
      _gaps.every((gap) => gap.isOwnedBy(cache)) &&
      _annotationGaps.every(
        (gap) => gap.lease != null && cache.ownsLease(gap.lease!),
      ) &&
      _spans.every(
        (item) => item.lease == null || cache.ownsLease(item.lease!),
      );
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    for (final column in _columns) ...column.nativeLeases,
    for (final gap in _gaps) ...gap.nativeLeases,
    for (final gap in _annotationGaps) ?gap.lease,
    for (final item in _spans) ?item.lease,
  ];
  int get columnCount => metrics.columns.length;
  int get spanCount => metrics.spans.length;
  ForumBodyRubyGroupLayout columnAt(int index) {
    _ensureActive();
    return _columns[index];
  }

  ForumBodyParagraphContent contentForSpan(int index) {
    _ensureActive();
    return _spans[index].content;
  }

  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    for (final (index, column) in _columns.indexed) {
      column.paint(canvas, offset + metrics.columnOffsets[index]);
    }
    for (final (index, gap) in _gaps.indexed) {
      gap.paint(canvas, offset + metrics.gaps[index].offset);
    }
    for (final (index, item) in _spans.indexed) {
      item.lease?.layout.paint(canvas, offset + metrics.spans[index].offset);
    }
    for (final (index, gap) in _annotationGaps.indexed) {
      gap.lease!.layout.paint(
        canvas,
        offset + metrics.annotationGaps[index].offset,
      );
    }
  }

  int? _spanFor(int column, int rank) {
    for (final index in _spanRanks[rank] ?? const <int>[]) {
      final span = metrics.spans[index];
      if (span.input.startColumn > column) break;
      if (column < span.input.endColumn && span.metrics.hasAnnotation) {
        return index;
      }
    }
    return null;
  }

  ForumBodyRubySegmentHit sourceAt(Offset point) {
    _ensureActive();
    if (!point.dx.isFinite || !point.dy.isFinite) {
      throw ArgumentError.value(point);
    }
    double distance(double coordinate, double start, double end) =>
        coordinate < start
        ? start - coordinate
        : coordinate > end
        ? coordinate - end
        : 0;
    var column = 0;
    int? gap;
    var horizontal = double.infinity;
    var left = double.negativeInfinity;
    for (var i = 0; i < columnCount; i++) {
      final start = metrics.columnLefts[i];
      final delta = distance(point.dx, start, start + metrics.columnWidths[i]);
      if (delta < horizontal || (delta == horizontal && start > left)) {
        column = i;
        horizontal = delta;
        left = start;
      }
    }
    for (var i = 0; i < _gaps.length; i++) {
      final item = metrics.gaps[i];
      final delta = distance(point.dx, item.left, item.left + item.width);
      if (delta < horizontal || (delta == horizontal && item.left > left)) {
        gap = i;
        horizontal = delta;
        left = item.left;
      }
    }
    int? edge = gap == null ? null : metrics.gaps[gap].input.beforeColumn;
    for (var i = 1; _annotationGaps.isNotEmpty && i < columnCount; i++) {
      final start = metrics.direction == TextDirection.ltr
          ? metrics.columnLefts[i - 1] + metrics.columnWidths[i - 1]
          : metrics.columnLefts[i] + metrics.columnWidths[i];
      final end = metrics.direction == TextDirection.ltr
          ? metrics.columnLefts[i]
          : metrics.columnLefts[i - 1];
      if (point.dx > start && point.dx < end) {
        edge = i;
        break;
      }
    }
    int? spanFor(int rank) {
      if (edge == null) return _spanFor(column, rank);
      for (final i in _spanRanks[rank] ?? const <int>[]) {
        final span = metrics.spans[i];
        if (span.input.startColumn >= edge) break;
        if (span.input.endColumn > edge && span.metrics.hasAnnotation) {
          return i;
        }
      }
      return null;
    }

    int? annotationGapFor(int rank) {
      if (edge == null) return null;
      int? found;
      var bestDistance = double.infinity;
      var bestLeft = double.negativeInfinity;
      for (final i in _annotationGapRanks[rank] ?? const <int>[]) {
        final item = metrics.annotationGaps[i];
        if (item.input.beforeColumn != edge) continue;
        final delta = distance(point.dx, item.left, item.left + item.width);
        if (delta < bestDistance ||
            (delta == bestDistance && item.left > bestLeft)) {
          found = i;
          bestDistance = delta;
          bestLeft = item.left;
        }
      }
      return found;
    }

    final own = gap == null ? metrics.columns[column] : metrics.gaps[gap].font;
    var selected = -1;
    var bestTop = own.baseBandTop;
    var best = distance(point.dy, own.baseBandTop, own.baseBandBottom);
    var nearest = -1;
    var nearestDistance = double.infinity;
    var nearestTop = double.negativeInfinity;
    for (var rank = 0; rank < own.annotations.length; rank++) {
      if (!(edge == null && own.annotations[rank].hasAnnotation) &&
          spanFor(rank) == null &&
          annotationGapFor(rank) == null) {
        continue;
      }
      final band = own.annotations[rank];
      final delta = distance(point.dy, band.bandTop, band.bandBottom);
      if (delta < nearestDistance ||
          (delta == nearestDistance && band.bandTop > nearestTop)) {
        nearest = rank;
        nearestDistance = delta;
        nearestTop = band.bandTop;
      }
      if (delta < best || (delta == best && band.bandTop > bestTop)) {
        selected = rank;
        best = delta;
        bestTop = band.bandTop;
      }
    }
    final forced =
        selected < 0 &&
        gap == null &&
        _columns[column]
            .contentFor(ForumBodyRubyPart.base)
            .projection
            .text
            .isEmpty;
    if (forced) selected = nearest;
    final annotationGap = selected < 0 ? null : annotationGapFor(selected);
    if (annotationGap != null) {
      final position = _annotationGaps[annotationGap].lease!.layout.sourceAt(
        point - metrics.annotationGaps[annotationGap].offset,
      );
      return ForumBodyRubySegmentHit._(
        annotationGapIndex: annotationGap,
        position: forced
            ? HtmlProjectedSourcePosition(
                sourceRune: position.sourceRune,
                displayUtf16: position.displayUtf16,
                isExact: false,
              )
            : position,
      );
    }
    final span = selected < 0 ? null : spanFor(selected);
    if (span != null) {
      final position = _spans[span].lease!.layout.sourceAt(
        point - metrics.spans[span].offset,
      );
      return ForumBodyRubySegmentHit._(
        spanIndex: span,
        position: forced
            ? HtmlProjectedSourcePosition(
                sourceRune: position.sourceRune,
                displayUtf16: position.displayUtf16,
                isExact: false,
              )
            : position,
      );
    }
    if (gap != null) {
      final hit = _gaps[gap].sourceAt(point - metrics.gaps[gap].offset);
      return ForumBodyRubySegmentHit._(gapIndex: gap, position: hit.position);
    }
    final hit = _columns[column].sourceAt(
      point - metrics.columnOffsets[column],
    );
    return ForumBodyRubySegmentHit._(
      columnIndex: column,
      columnHit: hit,
      position: hit.position,
    );
  }

  List<TextBox> selectionBoxesForColumn({
    required int columnIndex,
    required ForumBodyRubyPart part,
    required int startUtf16,
    required int endUtf16,
    int? annotationIndex,
  }) {
    _ensureActive();
    return _shift(
      _columns[columnIndex].selectionBoxes(
        part: part,
        startUtf16: startUtf16,
        endUtf16: endUtf16,
        annotationIndex: annotationIndex,
      ),
      metrics.columnOffsets[columnIndex],
    );
  }

  List<TextBox> selectionBoxesForGap({
    required int gapIndex,
    required int startUtf16,
    required int endUtf16,
  }) {
    _ensureActive();
    return _shift(
      _gaps[gapIndex].selectionBoxes(
        part: ForumBodyRubyPart.base,
        startUtf16: startUtf16,
        endUtf16: endUtf16,
      ),
      metrics.gaps[gapIndex].offset,
    );
  }

  List<TextBox> selectionBoxesForAnnotationGap({
    required int gapIndex,
    required int startUtf16,
    required int endUtf16,
  }) {
    _ensureActive();
    final gap = _annotationGaps[gapIndex];
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      gap.content.projection.text.length,
    );
    return _shift(
      gap.lease!.layout.selectionBoxes(startUtf16, endUtf16),
      metrics.annotationGaps[gapIndex].offset,
    );
  }

  List<TextBox> selectionBoxesForSpan({
    required int spanIndex,
    required int startUtf16,
    required int endUtf16,
  }) {
    _ensureActive();
    final item = _spans[spanIndex];
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      item.content.projection.text.length,
    );
    return item.lease == null
        ? const []
        : _shift(
            item.lease!.layout.selectionBoxes(startUtf16, endUtf16),
            metrics.spans[spanIndex].offset,
          );
  }

  static List<TextBox> _shift(List<TextBox> boxes, Offset offset) =>
      List.unmodifiable([
        for (final box in boxes)
          TextBox.fromLTRBD(
            box.left + offset.dx,
            box.top + offset.dy,
            box.right + offset.dx,
            box.bottom + offset.dy,
            box.direction,
          ),
      ]);
  static bool _sameScope(
    ForumBodyParagraphContent a,
    ForumBodyParagraphContent b,
  ) =>
      a.identity == b.identity &&
      a.fontRevision == b.fontRevision &&
      a.styleRevision == b.styleRevision;
  static bool _near(double a, double b) =>
      (a - b).abs() <= ForumBodyRubyGroupMetrics.geometryTolerance;
  static bool _sameAnnotation(
    ForumBodyRubyAnnotationMetrics a,
    ForumBodyRubyAnnotationMetrics b, {
    bool positions = true,
  }) =>
      a.side == b.side &&
      a.hasAnnotation == b.hasAnnotation &&
      _near(a.gap, b.gap) &&
      _near(a.fontBaseline, b.fontBaseline) &&
      a.bounds == b.bounds &&
      (!positions ||
          (a.offset == b.offset &&
              _near(a.bandTop, b.bandTop) &&
              _near(a.bandBottom, b.bandBottom)));
  static bool _sameColumnHeader(
    ForumBodyRubyGroupMetrics a,
    ForumBodyRubyGroupMetrics b,
  ) =>
      a.size == b.size &&
      _near(a.baseline, b.baseline) &&
      a.baseOffset == b.baseOffset &&
      _near(a.baseAscent, b.baseAscent) &&
      _near(a.baseDescent, b.baseDescent) &&
      _near(a.baseFontBaseline, b.baseFontBaseline) &&
      _near(a.baseBandTop, b.baseBandTop) &&
      _near(a.baseBandBottom, b.baseBandBottom) &&
      a.annotations.length == b.annotations.length;
  static Never _invalid([
    ForumBodyRubyGroupFailure failure = ForumBodyRubyGroupFailure.geometry,
  ]) => throw ForumBodyRubyGroupException(failure);
  void _ensureActive() {
    if (!isActive) throw StateError('Ruby segment layout is retired');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final columns = _columns;
    final gaps = _gaps;
    final spans = _spans;
    final annotationGaps = _annotationGaps;
    _columns = const [];
    _gaps = const [];
    _spans = const [];
    _annotationGaps = const [];
    _spanRanks.clear();
    _annotationGapRanks.clear();
    for (final column in columns) {
      column.close();
    }
    for (final gap in gaps) {
      gap.close();
    }
    for (final item in spans) {
      item.lease?.release();
    }
    for (final gap in annotationGaps) {
      gap.lease?.release();
    }
  }
}
