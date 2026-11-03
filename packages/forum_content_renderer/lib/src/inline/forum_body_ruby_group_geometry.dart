part of 'forum_body_ruby_group_metrics.dart';

/// Pure measured geometry of a text or composite inline child, in that child's
/// local coordinates. Only numeric values survive; no render/source proof does.
final class ForumBodyRubyChildMetrics {
  /// Capture the real native row and glyph overhang only after checking the
  /// current cache owner and the exact original leaf. Composite children use
  /// the numeric constructor; they never masquerade as native text leases.
  factory ForumBodyRubyChildMetrics.measure({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease lease,
    required ForumBodyParagraphContent content,
  }) {
    if (!cache.ownsLease(lease)) {
      throw StateError('Ruby child owner is retired');
    }
    if (!identical(lease.content, content)) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    return ForumBodyRubyChildMetrics(
      bounds: ForumBodyRubyGroupMetrics._textBounds(lease),
      alphabeticBaseline: lease.layout.alphabeticBaseline,
    );
  }

  ForumBodyRubyChildMetrics({
    required Rect bounds,
    required this.alphabeticBaseline,
  }) : bounds = Rect.fromLTRB(
         bounds.left,
         bounds.top,
         bounds.right,
         bounds.bottom,
       ) {
    if (!this.bounds.left.isFinite ||
        !this.bounds.top.isFinite ||
        !this.bounds.right.isFinite ||
        !this.bounds.bottom.isFinite ||
        this.bounds.width < 0 ||
        this.bounds.height < 0 ||
        !alphabeticBaseline.isFinite) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  final Rect bounds;
  final double alphabeticBaseline;
}

/// Single numeric stack algorithm for native text and composite/nested boxes.
/// Each append consumes one known child; final positioning yields by rank.
/// Callers retain all ownership, source, preparation and cancellation checks.
final class ForumBodyRubyGroupGeometry {
  ForumBodyRubyGroupGeometry({
    required List<({bool hasAnnotation, double gap, ForumBodyRubySide side})>
    annotations,
    this.maxWidth = 16384,
    this.level,
  }) : _inputs = List.of(annotations) {
    if (_inputs.isEmpty) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    if (!maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384 ||
        _inputs.any(
          (item) => !item.gap.isFinite || item.gap < 0 || item.gap > 16384,
        )) {
      ForumBodyRubyGroupMetrics._invalid();
    }
    if (level != null && level!.annotations.length != _inputs.length) {
      ForumBodyRubyGroupMetrics._invalid();
    }
  }
  List<({bool hasAnnotation, double gap, ForumBodyRubySide side})> _inputs;
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

  void addBase(ForumBodyRubyChildMetrics child) {
    _ensureActive();
    if (_baseBounds != null) throw StateError('Ruby base was already measured');
    final bounds = child.bounds;
    final baseline = child.alphabeticBaseline;
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

  void addAnnotation(ForumBodyRubyChildMetrics? child) {
    _ensureActive();
    if (_baseBounds == null || measuredAnnotations >= _inputs.length) {
      throw StateError('Ruby annotation is out of order');
    }
    final item = _inputs[measuredAnnotations];
    if (item.hasAnnotation != (child != null)) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    final raw = ForumBodyRubyAnnotationMetrics._fromGeometry(
      child: child,
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
    if (!isMeasured) throw StateError('Ruby child measurement is incomplete');
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
        baseFontBounds: _baseBounds!,
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
