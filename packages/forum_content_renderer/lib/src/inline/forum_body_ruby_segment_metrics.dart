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

/// One independently laid-out, unbroken ruby segment/component. Actual native
/// members are still independent; this result retains only numbers and sides.
final class ForumBodyRubySegmentMetrics {
  /// Synchronous callers drive the same bounded numeric worker as cooperative
  /// preparation. This does not shape, pin or prove any visible source.
  factory ForumBodyRubySegmentMetrics.compose({
    required List<ForumBodyRubyGroupMetrics> columns,
    required List<ForumBodyRubyMeasuredSpan> spans,
    TextDirection direction = TextDirection.ltr,
    double maxWidth = 16384,
  }) {
    final work = ForumBodyRubySegmentComposition(
      columns: columns,
      spans: spans,
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
  }) : columns = List.unmodifiable(columns),
       columnWidths = List.unmodifiable(columnWidths),
       columnLefts = List.unmodifiable(columnLefts),
       columnOffsets = List.unmodifiable(columnOffsets),
       spans = List.unmodifiable(spans);
  static const revision = 2;
  final Size size;
  final double baseline;
  final ForumBodyRubyLevelMetrics level;
  final TextDirection direction;
  final List<ForumBodyRubyGroupMetrics> columns;
  final List<double> columnWidths;
  final List<double> columnLefts;
  final List<Offset> columnOffsets;
  final List<ForumBodyRubyPlacedSpan> spans;
  PlaceholderDimensions get placeholderDimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );
}

enum _SegmentPhase {
  columns,
  spans,
  widths,
  sum,
  spread,
  prefix,
  levels,
  align,
  place,
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
    this.direction = TextDirection.ltr,
    this.maxWidth = 16384,
  }) : _columns = List.of(columns),
       _spans = List.of(spans),
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
  final TextDirection direction;
  final double maxWidth;
  final _union = ForumBodyRubyLevelUnion();
  final List<List<int>?> _buckets;
  final _widths = <double>[];
  final _prefix = <double>[0];
  final _positions = <({double baseline, double top, double bottom})>[];
  final _aligned = <ForumBodyRubyGroupMetrics>[];
  final _lefts = <double>[];
  final _offsets = <Offset>[];
  final _placed = <ForumBodyRubyPlacedSpan>[];
  final _lastEnd = <int, int>{};
  ForumBodyRubyLevelMerge? _merge;
  ForumBodyRubyColumnAlignment? _align;
  ForumBodyRubyLevelMetrics? _level;
  _RubyStack? _stack;
  var _phase = _SegmentPhase.columns;
  var _column = 0;
  var _span = 0;
  int? _cursor;
  var _bucketWidth = 1;
  var _bucketItem = 0;
  var _activeSpan = 0;
  double _sum = 0;
  double _extra = 0;
  double _over = 0;
  double _under = 0;
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
            _phase = _SegmentPhase.spans;
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
          _sum += _widths[_cursor!];
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
            _stack = _RubyStack(_level!.baseAscent, _level!.baseDescent);
            _over = _level!.baseAscent;
            _under = _level!.baseDescent;
            _phase = _SegmentPhase.levels;
            continue;
          }
          final sum = _prefix.last + _widths[_prefix.length - 1];
          if (!sum.isFinite || sum < 0) ForumBodyRubyGroupMetrics._invalid();
          if (sum > maxWidth) {
            throw const ForumBodyRubyGroupException(
              ForumBodyRubyGroupFailure.overflow,
            );
          }
          _prefix.add(sum);
          work++;
        case _SegmentPhase.levels:
          if (_positions.length == _level!.annotations.length) {
            final height = _over + _under;
            if (!height.isFinite ||
                height <= 0 ||
                height > 16384 ||
                !_over.isFinite ||
                _over < 0 ||
                _over > height) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            _phase = _SegmentPhase.align;
            continue;
          }
          final position = _stack!.append(
            _level!.annotations[_positions.length],
          );
          _positions.add(position);
          _over = math.max(_over, -position.top);
          _under = math.max(_under, position.bottom);
          work++;
        case _SegmentPhase.align:
          if (_aligned.length == _columns.length) {
            _phase = _SegmentPhase.place;
            continue;
          }
          final index = _aligned.length;
          final align = _align ??= ForumBodyRubyColumnAlignment(
            column: _columns[index],
            level: _level!,
            prepareResult: true,
          );
          work += align.advance(maxParts: maxParts - work);
          if (align.isComplete) {
            final left = direction == TextDirection.ltr
                ? _prefix[index]
                : _prefix.last - _prefix[index + 1];
            _aligned.add(align.result);
            _lefts.add(left);
            _offsets.add(
              Offset(left + (_widths[index] - align.result.size.width) / 2, 0),
            );
            _align = null;
          }
        case _SegmentPhase.place:
          if (_placed.length == _spans.length) {
            _result = ForumBodyRubySegmentMetrics._(
              direction: direction,
              size: Size(_prefix.last, _over + _under),
              baseline: _over,
              level: _level!,
              columns: _aligned,
              columnWidths: _widths,
              columnLefts: _lefts,
              columnOffsets: _offsets,
              spans: _placed,
            );
            _phase = _SegmentPhase.ready;
            work++;
            continue;
          }
          final span = _spans[_placed.length];
          final width = _prefix[span.endColumn] - _prefix[span.startColumn];
          final left = direction == TextDirection.ltr
              ? _prefix[span.startColumn]
              : _prefix.last - _prefix[span.endColumn];
          final position = _positions[span.annotationIndex];
          _placed.add(
            ForumBodyRubyPlacedSpan._(
              span,
              left,
              width,
              span.annotation._positioned(
                width: width,
                baseline: _over,
                relativeBaseline: position.baseline,
                top: position.top,
                bottom: position.bottom,
              ),
            ),
          );
          work++;
        case _SegmentPhase.ready || _SegmentPhase.failed:
          throw StateError('Ruby segment composition is not active');
      }
    }
    return work;
  }
}
