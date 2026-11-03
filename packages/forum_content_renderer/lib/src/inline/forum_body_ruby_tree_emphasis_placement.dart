part of 'forum_body_ruby_tree_input.dart';

/// One original source unit and its source-free marker in root coordinates.
/// Keep translations separate from the native font's fractional baseline.
final class ForumBodyRubyTreePlacedEmphasisMark {
  const ForumBodyRubyTreePlacedEmphasisMark._({
    required this.source,
    required this.mark,
    required this.row,
    required this.baselineOrigin,
    required this.fontOffset,
    required this.fontBounds,
  });
  final ForumBodyRubyTreeEmphasisSourceMetrics source;
  final ForumBodyEmphasisLineMark mark;
  final ForumBodyRubyPhysicalRow row;
  final Offset baselineOrigin, fontOffset;
  final Rect fontBounds;
}

final class ForumBodyRubyTreeEmphasisRow {
  const ForumBodyRubyTreeEmphasisRow._({
    required this.id,
    required this.parent,
    required this.annotationSide,
    required this.overBaseline,
    required this.underBaseline,
    required this.overAnnotationMarkerBounds,
    required this.underAnnotationMarkerBounds,
    required this.subtreeMarkerBounds,
  });
  final ForumBodyRubyPhysicalRow id;
  final ForumBodyRubyPhysicalRow? parent;
  final ForumBodyRubySide? annotationSide;
  final double? overBaseline, underBaseline;

  /// Annotation descendants only, excluding this row's own marks. Mixed
  /// parents need this clearance without treating base marks as annotations.
  final Rect? overAnnotationMarkerBounds, underAnnotationMarkerBounds;

  /// Marker fonts only, including annotation descendants. This never becomes
  /// an ancestor's glyph base or changes the font-only decoration bands.
  final Rect? subtreeMarkerBounds;
}

/// Numeric placement only: original glyph geometry, fonts and source contracts
/// remain in [input]. Visible binding must still qualify the complete tree and
/// marker fonts before acquiring a merged scene or claiming source coverage.
final class ForumBodyRubyTreeEmphasisPlacement {
  ForumBodyRubyTreeEmphasisPlacement._(
    this.input,
    this.bounds,
    List<ForumBodyRubyTreePlacedEmphasisMark> marks,
    List<ForumBodyRubyTreeEmphasisRow> rows,
    Map<ForumBodyRubyPhysicalRow, ForumBodyRubyTreeEmphasisRow> byRow,
  ) : marks = UnmodifiableListView(marks),
      rows = UnmodifiableListView(rows),
      _byRow = UnmodifiableMapView(byRow);
  final ForumBodyRubyTreeDecorationBands input;

  /// Includes the unchanged glyph plane, font reservations and all marker fonts.
  final Rect bounds;

  /// Original source order, then original eligible unit order.
  final List<ForumBodyRubyTreePlacedEmphasisMark> marks;

  /// Annotation descendants precede their base row.
  final List<ForumBodyRubyTreeEmphasisRow> rows;
  final Map<ForumBodyRubyPhysicalRow, ForumBodyRubyTreeEmphasisRow> _byRow;
  ForumBodyRubyTreeEmphasisRow rowForId(ForumBodyRubyPhysicalRow id) =>
      _byRow[id] ?? (throw ArgumentError.value(id, 'id'));
}

enum _TreePlacementPhase {
  contexts,
  collect,
  rows,
  marks,
  publish,
  ready,
  transferred,
  closed,
}

/// Explicit outward movement of one already measured root row. Keep a signed
/// delta from its original local baseline, never reconstruct that native local
/// value by subtracting a large parent's global glyph origin.
final class ForumBodyRubyRootEmphasisShift {
  ForumBodyRubyRootEmphasisShift({
    required this.original,
    this.over = 0,
    this.under = 0,
  }) {
    final row = original.rowForId(original.input.contexts.first.physicalRow);
    if (!over.isFinite ||
        !under.isFinite ||
        over > 0 ||
        under < 0 ||
        over < -16384 ||
        under > 16384 ||
        row.overBaseline == null && over != 0 ||
        row.underBaseline == null && under != 0) {
      throw ArgumentError('Invalid outward root emphasis shift');
    }
  }
  final ForumBodyRubyTreeEmphasisPlacement original;
  final double over, under;
}

/// Align each physical row/side once. Solve annotation rows before their bases
/// so an explicitly marked annotation's decorations also stay inside the base
/// marks. Each part visits one context, source, marker or row; no native work.
final class ForumBodyRubyTreeEmphasisPlacementPreparation {
  ForumBodyRubyTreeEmphasisPlacementPreparation({
    required ForumBodyRubyTreeDecorationBands input,
    required void Function() ensureOwner,
    ForumBodyRubyRootEmphasisShift? rootShift,
  }) : _input = input,
       _ensureOwner = ensureOwner,
       _bounds = input.bounds,
       _rootShift = rootShift {
    if (rootShift != null && !identical(rootShift.original.input, input)) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.source,
      );
    }
  }
  ForumBodyRubyRootEmphasisShift? _rootShift;
  ForumBodyRubyTreeDecorationBands? _input;
  void Function()? _ensureOwner;
  Rect _bounds;
  List<_TreeMarkerRowWork> _work = [];
  Map<ForumBodyRubyPhysicalRow, _TreeMarkerRowWork> _workByRow = {};
  List<_TreeMarkerInput> _pending = [];
  List<ForumBodyRubyTreePlacedEmphasisMark> _marks = [];
  List<ForumBodyRubyTreeEmphasisRow> _rows = [];
  Map<ForumBodyRubyPhysicalRow, ForumBodyRubyTreeEmphasisRow> _byRow = {};
  ForumBodyRubyTreeEmphasisPlacement? _result;
  var _phase = _TreePlacementPhase.contexts;
  int _index = 0, _unit = 0;
  bool _operating = false;
  bool get isReady => _phase == _TreePlacementPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      var parts = 0;
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _TreePlacementPhase.contexts:
            if (_index < _input!.contexts.length) {
              _context(_input!.contexts[_index++]);
            } else {
              _index = 0;
              _phase = _TreePlacementPhase.collect;
            }
          case _TreePlacementPhase.collect:
            final sources = _input!.input.sources;
            if (_index == sources.length) {
              _index = _work.length - 1;
              _phase = _TreePlacementPhase.rows;
            } else {
              final source = sources[_index];
              if (_unit < source.line.marks.length) {
                _collect(source, source.line.marks[_unit++]);
              } else {
                _unit = 0;
                _index++;
              }
            }
          case _TreePlacementPhase.rows:
            if (_index >= 0) {
              final work = _work[_index--],
                  row = work.solve(
                    rootShift: work.parent == null ? _rootShift : null,
                  );
              _rows.add(row);
              _byRow[row.id] = row;
              final bounds = row.subtreeMarkerBounds;
              if (bounds != null) {
                _check(bounds);
                _bounds = _bounds.expandToInclude(bounds);
                if (row.parent != null) {
                  _workByRow[row.parent]!.includeAnnotation(
                    bounds,
                    row.annotationSide!,
                  );
                }
              }
            } else {
              _work = [];
              _workByRow = {};
              _index = 0;
              _phase = _TreePlacementPhase.marks;
            }
          case _TreePlacementPhase.marks:
            if (_index < _pending.length) {
              _place(_pending[_index++]);
            } else {
              _pending = [];
              _phase = _TreePlacementPhase.publish;
            }
          case _TreePlacementPhase.publish:
            _check(_bounds);
            _result = ForumBodyRubyTreeEmphasisPlacement._(
              _input!,
              _bounds,
              _marks,
              _rows,
              _byRow,
            );
            _marks = [];
            _rows = [];
            _byRow = {};
            _phase = _TreePlacementPhase.ready;
          case _TreePlacementPhase.ready:
          case _TreePlacementPhase.transferred:
          case _TreePlacementPhase.closed:
            throw StateError('Ruby tree marker placement is retired');
        }
        parts++;
        _guard();
      }
      return parts;
    });
  }

  void _context(ForumBodyRubyTreeDecorationContext context) {
    final id = context.physicalRow;
    if (_workByRow.containsKey(id)) return;
    final position = context.position, parentPosition = position.parent;
    final parent = parentPosition == null
        ? null
        : _input!.nodeForId(parentPosition.id).physicalRow;
    if (parent != null && (parent == id || !_workByRow.containsKey(parent))) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.metrics,
      );
    }
    final work = _TreeMarkerRowWork(
      id,
      parent,
      id.rank == null ? null : _input!.nodes[id.owner].rows[id.rank!].side,
    );
    _work.add(work);
    _workByRow[id] = work;
  }

  void _collect(
    ForumBodyRubyTreeEmphasisSourceMetrics source,
    ForumBodyEmphasisLineMark mark,
  ) {
    final context = _input!.sourceForId(source.source.source.id),
        line = source.line,
        style = line
            .input
            .content
            .runs[line.input.units[mark.unitIndex].runIndex]
            .style;
    final item = _TreeMarkerInput(
      source,
      mark,
      context,
      style.textEmphasis.side,
    );
    _pending.add(item);
    _workByRow[context.physicalRow]!.include(item);
  }

  void _place(_TreeMarkerInput item) {
    final row = _byRow[item.context.physicalRow]!, mark = item.mark;
    final baseline = item.side == ForumBodyEmphasisSide.over
        ? row.overBaseline!
        : row.underBaseline!;
    final origin = Offset(item.context.position.origin.dx, baseline);
    final offset = Offset(
      mark.baseRelativeOffset.dx,
      -mark.scaledAlphabeticBaseline,
    );
    final bounds = mark.scaledFontBounds.shift(offset).shift(origin);
    _check(bounds);
    // Keep the exact native local baseline. Do not recover it by subtracting
    // a large source/root position from the final marker rectangle.
    _marks.add(
      ForumBodyRubyTreePlacedEmphasisMark._(
        source: item.source,
        mark: mark,
        row: row.id,
        baselineOrigin: origin,
        fontOffset: offset,
        fontBounds: bounds,
      ),
    );
  }

  static void _check(Rect bounds) {
    if (!bounds.isFinite ||
        !bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width > 16384 ||
        bounds.height > 16384) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.geometry,
      );
    }
  }

  ForumBodyRubyTreeEmphasisPlacement takePlacement() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby tree marker placement is incomplete');
    final result = _result!;
    _result = null;
    _phase = _TreePlacementPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby tree marker placement is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _TreePlacementPhase.closed ||
        _phase == _TreePlacementPhase.transferred) {
      throw StateError('Ruby tree marker placement is retired');
    }
    _ensureOwner!();
    if (_phase == _TreePlacementPhase.closed) {
      throw StateError('Ruby tree marker owner is retired');
    }
  }

  void _drop() {
    _input = null;
    _rootShift = null;
    _ensureOwner = null;
    _work = [];
    _workByRow = {};
    _pending = [];
    _marks = [];
    _rows = [];
    _byRow = {};
  }

  void close() {
    if (_phase == _TreePlacementPhase.closed ||
        _phase == _TreePlacementPhase.transferred) {
      return;
    }
    _phase = _TreePlacementPhase.closed;
    _result = null;
    _drop();
  }
}

final class _TreeMarkerInput {
  const _TreeMarkerInput(this.source, this.mark, this.context, this.side);
  final ForumBodyRubyTreeEmphasisSourceMetrics source;
  final ForumBodyEmphasisLineMark mark;
  final ForumBodyRubyTreeDecorationContext context;
  final ForumBodyEmphasisSide side;
}

final class _TreeMarkerSideWork {
  double? baseline, left, right, top, bottom, edge;
  void include(_TreeMarkerInput input) {
    final mark = input.mark,
        context = input.context,
        origin = context.position.origin,
        candidate = origin.dy + mark.baseRelativeAlphabeticBaseline,
        over = input.side == ForumBodyEmphasisSide.over;
    baseline = over
        ? _RubyDecorationEdges.min(baseline, candidate)
        : _RubyDecorationEdges.max(baseline, candidate);
    left = _RubyDecorationEdges.min(
      left,
      (mark.scaledFontBounds.left + mark.baseRelativeOffset.dx) + origin.dx,
    );
    right = _RubyDecorationEdges.max(
      right,
      (mark.scaledFontBounds.right + mark.baseRelativeOffset.dx) + origin.dx,
    );
    top = _RubyDecorationEdges.min(
      top,
      -mark.scaledAlphabeticBaseline + mark.scaledFontBounds.top,
    );
    bottom = _RubyDecorationEdges.max(
      bottom,
      -mark.scaledAlphabeticBaseline + mark.scaledFontBounds.bottom,
    );
    edge = over
        ? _RubyDecorationEdges.min(edge, context.baseAncestorOverEdge)
        : _RubyDecorationEdges.max(edge, context.baseAncestorUnderEdge);
  }

  Rect? solve({required bool over}) {
    if (baseline == null) return null;
    if (edge != null) {
      baseline = over
          ? math.min(baseline!, edge! - bottom!)
          : math.max(baseline!, edge! - top!);
    }
    return Rect.fromLTRB(left!, baseline! + top!, right!, baseline! + bottom!);
  }
}

final class _TreeMarkerRowWork {
  _TreeMarkerRowWork(this.id, this.parent, this.annotationSide);
  final ForumBodyRubyPhysicalRow id;
  final ForumBodyRubyPhysicalRow? parent;
  final ForumBodyRubySide? annotationSide;
  final over = _TreeMarkerSideWork(), under = _TreeMarkerSideWork();
  Rect? descendants, overDescendants, underDescendants;
  void include(_TreeMarkerInput input) =>
      (input.side == ForumBodyEmphasisSide.over ? over : under).include(input);
  void includeAnnotation(Rect bounds, ForumBodyRubySide side) {
    descendants = descendants?.expandToInclude(bounds) ?? bounds;
    if (side == ForumBodyRubySide.over) {
      overDescendants = overDescendants?.expandToInclude(bounds) ?? bounds;
      over.edge = _RubyDecorationEdges.min(over.edge, bounds.top);
    } else {
      underDescendants = underDescendants?.expandToInclude(bounds) ?? bounds;
      under.edge = _RubyDecorationEdges.max(under.edge, bounds.bottom);
    }
  }

  ForumBodyRubyTreeEmphasisRow solve({
    ForumBodyRubyRootEmphasisShift? rootShift,
  }) {
    var bounds = descendants;
    var above = over.solve(over: true), below = under.solve(over: false);
    if (rootShift != null) {
      final expected = rootShift.original.rowForId(id);
      if ((over.baseline == null) != (expected.overBaseline == null) ||
          (under.baseline == null) != (expected.underBaseline == null) ||
          over.baseline != null && expected.overBaseline! > over.baseline! ||
          under.baseline != null && expected.underBaseline! < under.baseline!) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.metrics,
        );
      }
      if (over.baseline != null) {
        over.baseline = expected.overBaseline! + rootShift.over;
        above = Rect.fromLTRB(
          above!.left,
          over.baseline! + over.top!,
          above.right,
          over.baseline! + over.bottom!,
        );
      }
      if (under.baseline != null) {
        under.baseline = expected.underBaseline! + rootShift.under;
        below = Rect.fromLTRB(
          below!.left,
          under.baseline! + under.top!,
          below.right,
          under.baseline! + under.bottom!,
        );
      }
    }
    if (above != null) bounds = bounds?.expandToInclude(above) ?? above;
    if (below != null) bounds = bounds?.expandToInclude(below) ?? below;
    return ForumBodyRubyTreeEmphasisRow._(
      id: id,
      parent: parent,
      annotationSide: annotationSide,
      overBaseline: over.baseline,
      underBaseline: under.baseline,
      overAnnotationMarkerBounds: overDescendants,
      underAnnotationMarkerBounds: underDescendants,
      subtreeMarkerBounds: bounds,
    );
  }
}
