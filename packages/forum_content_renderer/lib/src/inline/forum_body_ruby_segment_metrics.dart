part of 'forum_body_ruby_group_metrics.dart';

/// Original source order is retained even when width constraints are processed
/// shortest first. Numeric intervals never stand in for source/coverage proof.
final class ForumBodyRubyMeasuredSpan {
  const ForumBodyRubyMeasuredSpan({
    required this.startColumn,
    required this.endColumn,
    required this.annotationIndex,
    required this.annotation,
  });
  final int startColumn;
  final int endColumn;
  final int annotationIndex;
  final ForumBodyRubyAnnotationMetrics annotation;
}

final class ForumBodyRubyPlacedSpan {
  const ForumBodyRubyPlacedSpan._(
    this.input,
    this.left,
    this.width,
    this.metrics,
  );
  final ForumBodyRubyMeasuredSpan input;
  final double left;
  final double width;
  final ForumBodyRubyAnnotationMetrics metrics;
  Offset get offset => Offset(left, 0) + metrics.offset;
}

/// A real text member between base columns. The shared font-box/level numeric
/// value is reused, but this member never consumes a base or annotation index.
final class ForumBodyRubyMeasuredGap {
  const ForumBodyRubyMeasuredGap({
    required this.beforeColumn,
    required this.font,
  });
  final int beforeColumn;
  final ForumBodyRubyGroupMetrics font;
}

final class ForumBodyRubyPlacedGap {
  const ForumBodyRubyPlacedGap._(this.input, this.left, this.font);
  final ForumBodyRubyMeasuredGap input;
  final double left;
  final ForumBodyRubyGroupMetrics font;
  double get width => font.size.width;
  Offset get offset => Offset(left, 0);
}

/// One independently laid-out, unbroken ruby segment/component. Actual native
/// members are still independent; this result retains only numbers and sides.
final class ForumBodyRubySegmentMetrics {
  /// Synchronous callers drive the same bounded numeric worker as cooperative
  /// preparation. This does not shape, pin or prove any visible source.
  factory ForumBodyRubySegmentMetrics.compose({
    required List<ForumBodyRubyGroupMetrics> columns,
    required List<ForumBodyRubyMeasuredSpan> spans,
    List<ForumBodyRubyMeasuredGap> gaps = const [],
    TextDirection direction = TextDirection.ltr,
    double maxWidth = 16384,
  }) {
    final work = ForumBodyRubySegmentComposition(
      columns: columns,
      spans: spans,
      gaps: gaps,
      direction: direction,
      maxWidth: maxWidth,
    );
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return work.result;
  }

  ForumBodyRubySegmentMetrics._({
    required this.size,
    required this.baseline,
    required this.level,
    required this.direction,
    required List<ForumBodyRubyGroupMetrics> columns,
    required List<double> columnWidths,
    required List<double> columnLefts,
    required List<Offset> columnOffsets,
    required List<ForumBodyRubyPlacedSpan> spans,
    required List<ForumBodyRubyPlacedGap> gaps,
    // Only the terminal positioning worker transfers its private buffers here.
    // Reused horizontal vectors are already frozen. Publication never rescans N.
  }) : columns = UnmodifiableListView(columns),
       columnWidths = UnmodifiableListView(columnWidths),
       columnLefts = UnmodifiableListView(columnLefts),
       columnOffsets = UnmodifiableListView(columnOffsets),
       spans = UnmodifiableListView(spans),
       gaps = UnmodifiableListView(gaps);
  static const revision = 3;
  final Size size;
  final double baseline;
  final ForumBodyRubyLevelMetrics level;
  final TextDirection direction;
  final List<ForumBodyRubyGroupMetrics> columns;
  final List<double> columnWidths;
  final List<double> columnLefts;
  final List<Offset> columnOffsets;
  final List<ForumBodyRubyPlacedSpan> spans;
  final List<ForumBodyRubyPlacedGap> gaps;
  String get alignmentSignature => columns.first.alignmentSignature;

  bool needsLevelAlignment(ForumBodyRubyLevelMetrics target) {
    final work = ForumBodyRubySegmentAlignment(segment: this, level: target);
    while (!work.isComplete) {
      work.advance(maxParts: 32);
    }
    return work.hasChanges;
  }

  /// Changes only vertical geometry; all allocated horizontal intervals remain
  /// exactly those of this component, including RTL and overlapping ranks.
  ForumBodyRubySegmentMetrics alignedTo(ForumBodyRubyLevelMetrics target) {
    final work = ForumBodyRubySegmentAlignment(
      segment: this,
      level: target,
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
}

enum _SegmentPhase {
  columns,
  gaps,
  spans,
  widths,
  sum,
  spread,
  prefix,
  position,
  ready,
  failed,
}

/// Bounded numeric composition of actual measured column and span glyphs.
/// Each base/rank merge, covered-column check, width sum/distribution, prefix,
/// level and final member position consumes work. No native/cache/owner lives
/// here; the reading session can yield between every quantum.
final class ForumBodyRubySegmentComposition {
  ForumBodyRubySegmentComposition({
    required List<ForumBodyRubyGroupMetrics> columns,
    required List<ForumBodyRubyMeasuredSpan> spans,
    List<ForumBodyRubyMeasuredGap> gaps = const [],
    this.direction = TextDirection.ltr,
    this.maxWidth = 16384,
  }) : _columns = List.of(columns),
       _spans = List.of(spans),
       _gaps = List.of(gaps),
       _gapWidths = List.filled(columns.length, 0),
       _buckets = List.filled(columns.length + 1, null) {
    if (columns.isEmpty ||
        !maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  final List<ForumBodyRubyGroupMetrics> _columns;
  final List<ForumBodyRubyMeasuredSpan> _spans;
  final List<ForumBodyRubyMeasuredGap> _gaps;
  final List<double> _gapWidths;
  final _gapWithinEdge = <double>[];
  final TextDirection direction;
  final double maxWidth;
  final _union = ForumBodyRubyLevelUnion();
  final List<List<int>?> _buckets;
  final _widths = <double>[];
  final _prefix = <double>[0];
  final _lastEnd = <int, int>{};
  ForumBodyRubyLevelMerge? _merge;
  _RubySegmentPositioning? _positioning;
  ForumBodyRubyLevelMetrics? _level;
  var _phase = _SegmentPhase.columns;
  var _column = 0;
  var _gap = 0;
  var _gapRank = 0;
  var _span = 0;
  int? _cursor;
  var _bucketWidth = 1;
  var _bucketItem = 0;
  var _activeSpan = 0;
  double _sum = 0;
  double _extra = 0;
  ForumBodyRubySegmentMetrics? _result;
  bool get isComplete => _phase == _SegmentPhase.ready;
  ForumBodyRubySegmentMetrics get result {
    if (!isComplete) throw StateError('Ruby segment composition is incomplete');
    return _result!;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete || _phase == _SegmentPhase.failed) {
      throw StateError('Ruby segment composition is not active');
    }
    try {
      return _advance(maxParts);
    } catch (_) {
      _phase = _SegmentPhase.failed;
      rethrow;
    }
  }

  int _advance(int maxParts) {
    var work = 0;
    while (work < maxParts && !isComplete) {
      switch (_phase) {
        case _SegmentPhase.columns:
          if (_column == _columns.length) {
            _phase = _SegmentPhase.gaps;
            continue;
          }
          final column = _columns[_column];
          final merge = _merge ??= _union.merge(column);
          work += merge.advance(maxParts: maxParts - work);
          if (merge.isComplete) {
            _widths.add(column.size.width);
            _column++;
            _merge = null;
          }
        case _SegmentPhase.gaps:
          if (_gap == _gaps.length) {
            _phase = _SegmentPhase.spans;
            continue;
          }
          final gap = _gaps[_gap];
          if (_gapRank == 0 && _merge == null) {
            if (gap.beforeColumn <= 0 ||
                gap.beforeColumn >= _columns.length ||
                (_gap > 0 && gap.beforeColumn < _gaps[_gap - 1].beforeColumn)) {
              ForumBodyRubyGroupMetrics._invalid();
            }
          }
          if (_gapRank < gap.font.annotations.length) {
            if (gap.font.annotations[_gapRank++].hasAnnotation) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            work++;
            continue;
          }
          final merge = _merge ??= _union.merge(gap.font);
          work += merge.advance(maxParts: maxParts - work);
          if (merge.isComplete) {
            _gapWithinEdge.add(_gapWidths[gap.beforeColumn]);
            _gapWidths[gap.beforeColumn] += gap.font.size.width;
            _gap++;
            _gapRank = 0;
            _merge = null;
          }
        case _SegmentPhase.spans:
          if (_span == _spans.length) {
            _level = _union.value;
            _phase = _SegmentPhase.widths;
            continue;
          }
          final span = _spans[_span];
          if (_cursor == null) {
            if (span.startColumn < 0 ||
                span.endColumn > _columns.length ||
                span.startColumn >= span.endColumn ||
                span.annotationIndex < 0 ||
                span.annotationIndex >= _union._annotations.length ||
                span.annotation.side !=
                    _union._annotations[span.annotationIndex].side ||
                span.startColumn < (_lastEnd[span.annotationIndex] ?? 0)) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            _cursor = span.startColumn;
            work++;
            continue;
          }
          if (_cursor! < span.endColumn) {
            if (_columns[_cursor!]
                .annotations[span.annotationIndex]
                .hasAnnotation) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            _cursor = _cursor! + 1;
            work++;
            continue;
          }
          final rank = span.annotationIndex;
          _union._annotations[rank] = _union._annotations[rank]._include(
            span.annotation,
          );
          _union._snapshot = null;
          _lastEnd[rank] = span.endColumn;
          final length = span.endColumn - span.startColumn;
          (_buckets[length] ??= []).add(_span);
          _span++;
          _cursor = null;
          work++;
        case _SegmentPhase.widths:
          if (_bucketWidth == _buckets.length) {
            _phase = _SegmentPhase.prefix;
            continue;
          }
          final bucket = _buckets[_bucketWidth];
          if (bucket == null || _bucketItem == bucket.length) {
            _bucketWidth++;
            _bucketItem = 0;
          } else {
            _activeSpan = bucket[_bucketItem++];
            _cursor = _spans[_activeSpan].startColumn;
            _sum = 0;
            _phase = _SegmentPhase.sum;
          }
          work++;
        case _SegmentPhase.sum:
          final span = _spans[_activeSpan];
          if (_cursor! == span.endColumn) {
            _extra =
                math.max(0, span.annotation.bounds.width - _sum) /
                (span.endColumn - span.startColumn);
            _cursor = span.startColumn;
            _phase = _SegmentPhase.spread;
            continue;
          }
          _sum +=
              _widths[_cursor!] +
              (_cursor! > span.startColumn ? _gapWidths[_cursor!] : 0);
          _cursor = _cursor! + 1;
          work++;
        case _SegmentPhase.spread:
          final span = _spans[_activeSpan];
          if (_cursor! == span.endColumn) {
            _phase = _SegmentPhase.widths;
            continue;
          }
          _widths[_cursor!] += _extra;
          _cursor = _cursor! + 1;
          work++;
        case _SegmentPhase.prefix:
          if (_prefix.length == _columns.length + 1) {
            _phase = _SegmentPhase.position;
            continue;
          }
          final index = _prefix.length - 1;
          final sum = _prefix.last + _gapWidths[index] + _widths[index];
          if (!sum.isFinite || sum < 0) ForumBodyRubyGroupMetrics._invalid();
          if (sum > maxWidth) {
            throw const ForumBodyRubyGroupException(
              ForumBodyRubyGroupFailure.overflow,
            );
          }
          _prefix.add(sum);
          work++;
        case _SegmentPhase.position:
          final positioning = _positioning ??= _RubySegmentPositioning(
            _RubyComposedHorizontal(
              columns: _columns,
              widths: _widths,
              prefix: _prefix,
              spans: _spans,
              gaps: _gaps,
              gapWidths: _gapWidths,
              gapWithinEdge: _gapWithinEdge,
              direction: direction,
            ),
            _level!,
          );
          work += positioning.advance(maxParts: maxParts - work);
          if (positioning.isComplete) {
            _result = positioning.result;
            _phase = _SegmentPhase.ready;
          }
        case _SegmentPhase.ready || _SegmentPhase.failed:
          throw StateError('Ruby segment composition is not active');
      }
    }
    return work;
  }
}
