part of 'forum_body_ruby_group_metrics.dart';

/// Internal mutable union, published only between completed column merges.
/// One merge charges its base and each original rank separately. Snapshots are
/// immutable numeric values; updating a union never changes earlier targets.
final class ForumBodyRubyLevelUnion {
  ForumBodyRubyLevelUnion();
  ForumBodyRubyLevelUnion.fromLevel(ForumBodyRubyLevelMetrics level)
    : _baseAscent = level.baseAscent,
      _baseDescent = level.baseDescent,
      _annotations = List.of(level.annotations);
  double? _baseAscent;
  double? _baseDescent;
  List<ForumBodyRubyAnnotationLevelMetrics> _annotations = [];
  bool _merging = false;
  ForumBodyRubyLevelMetrics? _snapshot;

  ForumBodyRubyLevelMerge merge(ForumBodyRubyGroupMetrics column) {
    if (_merging) throw StateError('Ruby union merge is already active');
    if (_annotations.isNotEmpty &&
        _annotations.length != column.annotations.length) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    _snapshot = null;
    _merging = true;
    return ForumBodyRubyLevelMerge._(this, column);
  }

  ForumBodyRubyLevelMetrics get value {
    if (_merging || _baseAscent == null) {
      throw StateError('Ruby union is incomplete');
    }
    return _snapshot ??= ForumBodyRubyLevelMetrics._(
      baseAscent: _baseAscent!,
      baseDescent: _baseDescent!,
      annotations: _annotations,
    );
  }
}

final class ForumBodyRubyLevelMerge {
  ForumBodyRubyLevelMerge._(this._union, this._column);
  final ForumBodyRubyLevelUnion _union;
  final ForumBodyRubyGroupMetrics _column;
  bool _baseMerged = false;
  int _rank = 0;
  bool get isComplete => _baseMerged && _rank == _column.annotations.length;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete) throw StateError('Ruby union merge is complete');
    var parts = 0;
    if (!_baseMerged) {
      _union._baseAscent = _union._baseAscent == null
          ? _column.baseAscent
          : math.max(_union._baseAscent!, _column.baseAscent);
      _union._baseDescent = _union._baseDescent == null
          ? _column.baseDescent
          : math.max(_union._baseDescent!, _column.baseDescent);
      _baseMerged = true;
      parts++;
    }
    while (_rank < _column.annotations.length && parts < maxParts) {
      final item = _column.annotations[_rank];
      if (_rank == _union._annotations.length) {
        _union._annotations.add(
          ForumBodyRubyAnnotationLevelMetrics._single(item),
        );
      } else {
        final old = _union._annotations[_rank];
        if (old.side != item.side) ForumBodyRubyGroupMetrics._invalid();
        _union._annotations[_rank] = old._include(item);
      }
      _rank++;
      parts++;
    }
    if (isComplete) _union._merging = false;
    return parts;
  }
}

/// Internal rank-by-rank validation/check and optional result positioning.
/// Relative geometry uses the same stack primitive as native measurement.
/// A changed early rank never skips validation of a later incompatible rank.
final class ForumBodyRubyColumnAlignment {
  ForumBodyRubyColumnAlignment({
    required this.column,
    required this.level,
    this.prepareResult = false,
  }) : _stack = _RubyStack(level.baseAscent, level.baseDescent),
       _over = level.baseAscent,
       _under = level.baseDescent {
    const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
    if (column.annotations.length != level.annotations.length ||
        column.baseAscent > level.baseAscent + tolerance ||
        column.baseDescent > level.baseDescent + tolerance) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  final ForumBodyRubyGroupMetrics column;
  final ForumBodyRubyLevelMetrics level;
  final bool prepareResult;
  final _RubyStack _stack;
  double _over;
  double _under;
  final _positions = <({double baseline, double top, double bottom})>[];
  final _annotations = <ForumBodyRubyAnnotationMetrics>[];
  int _rank = 0;
  bool _changed = false;
  ForumBodyRubyGroupMetrics? _result;
  bool get isComplete =>
      _rank == column.annotations.length && (!prepareResult || _result != null);
  bool get hasChanges {
    if (!isComplete) throw StateError('Ruby alignment check is incomplete');
    return _changed;
  }

  ForumBodyRubyGroupMetrics get result {
    if (!isComplete || !prepareResult) {
      throw StateError('Ruby alignment result is incomplete');
    }
    return _result!;
  }

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (isComplete) throw StateError('Ruby alignment is complete');
    var parts = 0;
    while (_rank < column.annotations.length && parts < maxParts) {
      final annotation = column.annotations[_rank];
      final target = level.annotations[_rank];
      if (!target._contains(annotation)) ForumBodyRubyGroupMetrics._invalid();
      final position = _stack.append(target);
      _over = math.max(_over, -position.top);
      _under = math.max(_under, position.bottom);
      if (annotation.hasAnnotation &&
          ((annotation.fontBaseline + annotation.offset.dy - column.baseline) -
                      position.baseline)
                  .abs() >
              ForumBodyRubyGroupMetrics.geometryTolerance) {
        _changed = true;
      }
      if (prepareResult) _positions.add(position);
      _rank++;
      parts++;
    }
    if (_rank != column.annotations.length || !prepareResult) return parts;
    final over = _over;
    final height = over + _under;
    if (!height.isFinite ||
        height <= 0 ||
        height > 16384 ||
        !over.isFinite ||
        over < 0 ||
        over > height) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    while (_annotations.length < column.annotations.length &&
        parts < maxParts) {
      final index = _annotations.length;
      final position = _positions[index];
      _annotations.add(
        column.annotations[index]._positioned(
          width: column.size.width,
          baseline: over,
          relativeBaseline: position.baseline,
          top: position.top,
          bottom: position.bottom,
        ),
      );
      parts++;
    }
    if (_annotations.length == column.annotations.length) {
      _result = ForumBodyRubyGroupMetrics._(
        size: Size(column.size.width, height),
        baseline: over,
        baseOffset: Offset(
          column.baseOffset.dx,
          over - column.baseFontBaseline,
        ),
        baseBandTop: over - level.baseAscent,
        baseBandBottom: over + level.baseDescent,
        baseFontBaseline: column.baseFontBaseline,
        baseAscent: column.baseAscent,
        baseDescent: column.baseDescent,
        annotations: _annotations,
        alignmentSignature: column.alignmentSignature,
      );
    }
    return parts;
  }
}
