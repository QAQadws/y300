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
    required this.position,
  });
  final int? columnIndex;
  final ForumBodyRubyHit? columnHit;
  final int? spanIndex;
  final HtmlProjectedSourcePosition position;
}

typedef ForumBodyRubySegmentAnnotation = ({
  ForumBodyParagraphContent content,
  ForumBodyTextLease? lease,
});

/// An unbroken span component, consuming already-prepared column groups and
/// exactly one lease for each nonempty original spanning annotation. The
/// existing reading cache owns all glyphs; this port adds no cache or shaper.
final class ForumBodyRubySegmentLayout {
  ForumBodyRubySegmentLayout._(
    this._columns,
    this._spans,
    this.metrics,
    this._spanRanks,
  );

  /// Consumes ONLY these supplied handles on both success and failure. The
  /// numeric result cannot replace actual owner/content/paint/geometry checks.
  factory ForumBodyRubySegmentLayout.adopt({
    required ForumBodyParagraphCache cache,
    required List<ForumBodyRubyGroupLayout> columns,
    required List<ForumBodyRubySegmentAnnotation> spans,
    required ForumBodyRubySegmentMetrics metrics,
  }) {
    final inputs = List.of(columns);
    final annotations = List.of(spans);
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
      );
      for (final column in inputs) {
        assembly.addColumn(column);
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
      while (!assembly.isReady) {
        assembly.advance(maxParts: 32);
      }
      return assembly.takeLayout();
    } catch (_) {
      for (final column in inputs) {
        column.close();
      }
      for (final item in annotations) {
        item.lease?.release();
      }
      rethrow;
    } finally {
      assembly?.close();
    }
  }

  List<ForumBodyRubyGroupLayout> _columns;
  List<ForumBodyRubySegmentAnnotation> _spans;
  final Map<int, List<int>> _spanRanks;
  final ForumBodyRubySegmentMetrics metrics;
  bool _closed = false;
  Size get size => metrics.size;
  double get baseline => metrics.baseline;
  bool get isActive =>
      !_closed &&
      _columns.every((column) => column.isActive) &&
      _spans.every(
        (item) =>
            item.lease == null ||
            (item.lease!.isActive && item.lease!.layout.isPaintPrepared),
      );
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive &&
      _columns.every((column) => column.isOwnedBy(cache)) &&
      _spans.every(
        (item) => item.lease == null || cache.ownsLease(item.lease!),
      );
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    for (final column in _columns) ...column.nativeLeases,
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
    for (final (index, item) in _spans.indexed) {
      item.lease?.layout.paint(canvas, offset + metrics.spans[index].offset);
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
    final own = metrics.columns[column];
    var selected = -1;
    var bestTop = own.baseBandTop;
    var best = distance(point.dy, own.baseBandTop, own.baseBandBottom);
    var nearest = -1;
    var nearestDistance = double.infinity;
    var nearestTop = double.negativeInfinity;
    for (var rank = 0; rank < own.annotations.length; rank++) {
      if (!own.annotations[rank].hasAnnotation &&
          _spanFor(column, rank) == null) {
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
        _columns[column]
            .contentFor(ForumBodyRubyPart.base)
            .projection
            .text
            .isEmpty;
    if (forced) selected = nearest;
    final span = selected < 0 ? null : _spanFor(column, selected);
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
    final spans = _spans;
    _columns = const [];
    _spans = const [];
    _spanRanks.clear();
    for (final column in columns) {
      column.close();
    }
    for (final item in spans) {
      item.lease?.release();
    }
  }
}
