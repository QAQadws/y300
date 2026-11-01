part of 'forum_body_ruby_group_metrics.dart';

/// Horizontal geometry is fixed before vertical positioning. Re-aligning a
/// physical row borrows the original rectangles instead of re-solving widths.
sealed class _RubySegmentHorizontal {
  const _RubySegmentHorizontal();
  List<ForumBodyRubyGroupMetrics> get columns;
  List<double> get widths;
  TextDirection get direction;
  double get width;
  int get spanCount;
  double columnLeft(int index);
  ({ForumBodyRubyMeasuredSpan input, double left, double width}) span(
    int index,
  );
}

final class _RubyComposedHorizontal extends _RubySegmentHorizontal {
  const _RubyComposedHorizontal({
    required this.columns,
    required this.widths,
    required this.prefix,
    required this.spans,
    required this.direction,
  });
  @override
  final List<ForumBodyRubyGroupMetrics> columns;
  @override
  final List<double> widths;
  final List<double> prefix;
  final List<ForumBodyRubyMeasuredSpan> spans;
  @override
  final TextDirection direction;
  @override
  double get width => prefix.last;
  @override
  int get spanCount => spans.length;
  @override
  double columnLeft(int index) => direction == TextDirection.ltr
      ? prefix[index]
      : prefix.last - prefix[index + 1];
  @override
  ({ForumBodyRubyMeasuredSpan input, double left, double width}) span(
    int index,
  ) {
    final input = spans[index];
    return (
      input: input,
      left: direction == TextDirection.ltr
          ? prefix[input.startColumn]
          : prefix.last - prefix[input.endColumn],
      width: prefix[input.endColumn] - prefix[input.startColumn],
    );
  }
}

final class _RubyExistingHorizontal extends _RubySegmentHorizontal {
  const _RubyExistingHorizontal(this.metrics);
  final ForumBodyRubySegmentMetrics metrics;
  @override
  List<ForumBodyRubyGroupMetrics> get columns => metrics.columns;
  @override
  List<double> get widths => metrics.columnWidths;
  @override
  TextDirection get direction => metrics.direction;
  @override
  double get width => metrics.size.width;
  @override
  int get spanCount => metrics.spans.length;
  @override
  double columnLeft(int index) => metrics.columnLefts[index];
  @override
  ({ForumBodyRubyMeasuredSpan input, double left, double width}) span(
    int index,
  ) {
    final item = metrics.spans[index];
    return (input: item.input, left: item.left, width: item.width);
  }
}

enum _RubyPositionPhase { levels, columns, spans, publish, ready }

/// Sole component positioning path for intrinsic composition and row targets.
/// Each rank/member and final publication is charged; no glyph is re-measured.
final class _RubySegmentPositioning {
  _RubySegmentPositioning(this.horizontal, this.level)
    : _stack = _RubyStack(level.baseAscent, level.baseDescent),
      _over = level.baseAscent,
      _under = level.baseDescent;
  final _RubySegmentHorizontal horizontal;
  final ForumBodyRubyLevelMetrics level;
  final _RubyStack _stack;
  double _over;
  double _under;
  final _positions = <({double baseline, double top, double bottom})>[];
  final _columns = <ForumBodyRubyGroupMetrics>[];
  final _lefts = <double>[];
  final _offsets = <Offset>[];
  final _spans = <ForumBodyRubyPlacedSpan>[];
  ForumBodyRubyColumnAlignment? _columnWork;
  var _phase = _RubyPositionPhase.levels;
  ForumBodyRubySegmentMetrics? _result;
  bool get isComplete => _phase == _RubyPositionPhase.ready;
  ForumBodyRubySegmentMetrics get result {
    if (!isComplete) throw StateError('Ruby segment positioning is incomplete');
    return _result!;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete) throw StateError('Ruby segment positioning is complete');
    var work = 0;
    while (work < maxParts && !isComplete) {
      switch (_phase) {
        case _RubyPositionPhase.levels:
          if (_positions.length == level.annotations.length) {
            final height = _over + _under;
            if (!height.isFinite ||
                height <= 0 ||
                height > 16384 ||
                !_over.isFinite ||
                _over < 0 ||
                _over > height) {
              ForumBodyRubyGroupMetrics._invalid();
            }
            _phase = _RubyPositionPhase.columns;
            continue;
          }
          final position = _stack.append(level.annotations[_positions.length]);
          _positions.add(position);
          _over = math.max(_over, -position.top);
          _under = math.max(_under, position.bottom);
          work++;
        case _RubyPositionPhase.columns:
          if (_columns.length == horizontal.columns.length) {
            _phase = _RubyPositionPhase.spans;
            continue;
          }
          final index = _columns.length;
          final alignment = _columnWork ??= ForumBodyRubyColumnAlignment(
            column: horizontal.columns[index],
            level: level,
            prepareResult: true,
          );
          work += alignment.advance(maxParts: maxParts - work);
          if (alignment.isComplete) {
            final left = horizontal.columnLeft(index);
            _columns.add(alignment.result);
            _lefts.add(left);
            _offsets.add(
              Offset(
                left +
                    (horizontal.widths[index] - alignment.result.size.width) /
                        2,
                0,
              ),
            );
            _columnWork = null;
          }
        case _RubyPositionPhase.spans:
          if (_spans.length == horizontal.spanCount) {
            _phase = _RubyPositionPhase.publish;
            continue;
          }
          final item = horizontal.span(_spans.length);
          final position = _positions[item.input.annotationIndex];
          _spans.add(
            ForumBodyRubyPlacedSpan._(
              item.input,
              item.left,
              item.width,
              item.input.annotation._positioned(
                width: item.width,
                baseline: _over,
                relativeBaseline: position.baseline,
                top: position.top,
                bottom: position.bottom,
              ),
            ),
          );
          work++;
        case _RubyPositionPhase.publish:
          _result = ForumBodyRubySegmentMetrics._(
            direction: horizontal.direction,
            size: Size(horizontal.width, _over + _under),
            baseline: _over,
            level: level,
            columns: _columns,
            columnWidths: horizontal.widths,
            columnLefts: _lefts,
            columnOffsets: _offsets,
            spans: _spans,
          );
          _phase = _RubyPositionPhase.ready;
          work++;
        case _RubyPositionPhase.ready:
          throw StateError('Ruby segment positioning is complete');
      }
    }
    return work;
  }
}

/// Validate all actual ranks, including span-only glyph extents, before optional
/// vertical positioning. An early shift cannot hide a later invalid target.
final class ForumBodyRubySegmentAlignment {
  ForumBodyRubySegmentAlignment({
    required this.segment,
    required this.level,
    this.prepareResult = false,
  }) : _source = _RubyStack(
         segment.level.baseAscent,
         segment.level.baseDescent,
       ),
       _target = _RubyStack(level.baseAscent, level.baseDescent) {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    if (segment.level.annotations.length != level.annotations.length ||
        segment.level.baseAscent > level.baseAscent + tolerance ||
        segment.level.baseDescent > level.baseDescent + tolerance) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  final ForumBodyRubySegmentMetrics segment;
  final ForumBodyRubyLevelMetrics level;
  final bool prepareResult;
  final _RubyStack _source;
  final _RubyStack _target;
  var _rank = 0;
  var _changed = false;
  _RubySegmentPositioning? _positioning;
  bool get isComplete =>
      _rank == level.annotations.length &&
      (!prepareResult || (_positioning?.isComplete ?? false));
  bool get hasChanges {
    if (!isComplete) throw StateError('Ruby segment alignment is incomplete');
    return _changed;
  }

  ForumBodyRubySegmentMetrics get result {
    if (!isComplete || !prepareResult) {
      throw StateError('Ruby segment alignment result is incomplete');
    }
    return _positioning!.result;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete) throw StateError('Ruby segment alignment is complete');
    var work = 0;
    while (_rank < level.annotations.length && work < maxParts) {
      final source = segment.level.annotations[_rank];
      final target = level.annotations[_rank];
      if (!target._containsLevel(source)) ForumBodyRubyGroupMetrics._invalid();
      final before = _source.append(source);
      final after = _target.append(target);
      if (source.hasAnnotation &&
          (before.baseline - after.baseline).abs() >
              ForumBodyRubyGroupMetrics.geometryTolerance) {
        _changed = true;
      }
      _rank++;
      work++;
    }
    if (_rank == level.annotations.length && prepareResult && work < maxParts) {
      final positioning = _positioning ??= _RubySegmentPositioning(
        _RubyExistingHorizontal(segment),
        level,
      );
      work += positioning.advance(maxParts: maxParts - work);
    }
    return work;
  }
}
