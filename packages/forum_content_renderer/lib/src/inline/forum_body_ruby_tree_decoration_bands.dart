part of 'forum_body_ruby_tree_input.dart';

/// Structural identity of a physical glyph row, not equality of floating-point
/// baselines. A null rank denotes the root base row.
typedef ForumBodyRubyPhysicalRow = ({int owner, int? rank});

/// Font-only clearance in the original node's coordinates. These virtual rows
/// never reposition the actual glyphs or include an emphasis marker envelope.
final class ForumBodyRubyTreeDecorationBand {
  const ForumBodyRubyTreeDecorationBand._({
    required this.rank,
    required this.side,
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.usesEmptyFont,
  });
  final int rank;
  final ForumBodyRubySide side;
  final double top, bottom, baseline;
  final bool usesEmptyFont;
  bool get isReserved => bottom > top;
}

final class ForumBodyRubyTreeDecorationNode {
  ForumBodyRubyTreeDecorationNode._({
    required this.id,
    required this.box,
    required this.isFontOnly,
    required int targets,
    required List<ForumBodyRubyTreeDecorationBand> rows,
    required this.localOverEdge,
    required this.localUnderEdge,
  }) : _targets = targets,
       rows = UnmodifiableListView(rows);
  final int id;

  /// Font envelope with the original alphabetic baseline. For an empty RT this
  /// is an unpositioned font input: its missing glyph origin has no paint meaning.
  final ForumBodyRubyChildMetrics? box;
  final bool isFontOnly;
  final int _targets;
  final List<ForumBodyRubyTreeDecorationBand> rows;
  final double? localOverEdge, localUnderEdge;
}

final class ForumBodyRubyTreeDecorationContext {
  const ForumBodyRubyTreeDecorationContext._({
    required this.position,
    required this.node,
    required this.physicalRow,
    required this.physicalBaseline,
    required this.baseAncestorOverEdge,
    required this.baseAncestorUnderEdge,
  });
  final ForumBodyRubyTreeNodePosition position;
  final ForumBodyRubyTreeDecorationNode node;
  final ForumBodyRubyPhysicalRow physicalRow;
  final double physicalBaseline;
  final double? baseAncestorOverEdge, baseAncestorUnderEdge;
}

/// Pure decoration clearance attached to the original measured glyph tree.
/// Empty RTs reserve their natural font only for same-side marked base spans.
/// Marker placement, auto-hide policy, visible binding and coverage are separate.
final class ForumBodyRubyTreeDecorationBands {
  ForumBodyRubyTreeDecorationBands._(
    this.input,
    List<ForumBodyRubyTreeDecorationNode> nodes,
    List<ForumBodyRubyTreeDecorationContext> contexts,
    Map<int, ForumBodyRubyTreeDecorationContext> byNode,
  ) : nodes = UnmodifiableListView(nodes),
      contexts = UnmodifiableListView(contexts),
      _byNode = UnmodifiableMapView(byNode);
  final ForumBodyRubyTreeEmphasisMetrics input;

  /// Original postorder namespace.
  final List<ForumBodyRubyTreeDecorationNode> nodes;

  /// Original preorder; parent contexts share prefixes without copying ancestry.
  final List<ForumBodyRubyTreeDecorationContext> contexts;
  final Map<int, ForumBodyRubyTreeDecorationContext> _byNode;
  Rect get bounds => nodes.last.box!.bounds;
  ForumBodyRubyTreeDecorationContext nodeForId(int id) =>
      _byNode[id] ?? (throw ArgumentError.value(id, 'id'));

  /// Negative IDs retain their opaque native parent, never an inferred inner row.
  ForumBodyRubyTreeDecorationContext sourceForId(int id) =>
      nodeForId(input.geometry.sourceForId(id).node.id);
}

enum _DecorationPhase { nodes, contexts, publish, ready, transferred, closed }

/// Postorder font envelopes followed by preorder row/ancestor contexts. A part
/// visits one mark, rank, child, prefix entry, pending font or context. Publication
/// transfers append-only storage; no native work or unbounded final copy occurs.
final class ForumBodyRubyTreeDecorationBandsPreparation {
  ForumBodyRubyTreeDecorationBandsPreparation({
    required ForumBodyRubyTreeEmphasisMetrics input,
    required void Function() ensureOwner,
  }) : _input = input,
       _ensureOwner = ensureOwner;
  ForumBodyRubyTreeEmphasisMetrics? _input;
  void Function()? _ensureOwner;
  List<ForumBodyRubyTreeDecorationNode> _nodes = [];
  List<ForumBodyRubyTreeDecorationContext> _contexts = [];
  Map<int, ForumBodyRubyTreeDecorationContext> _byNode = {};
  _DecorationNodeWork? _work;
  ForumBodyRubyTreeDecorationBands? _result;
  var _phase = _DecorationPhase.nodes;
  int _index = 0;
  bool _operating = false;
  bool get isReady => _phase == _DecorationPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      var parts = 0;
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _DecorationPhase.nodes:
            if (_nodes.length == _input!.geometry.metrics.nodes.length) {
              _phase = _DecorationPhase.contexts;
            } else {
              final work = _work ??= _DecorationNodeWork(
                _input!,
                _nodes.length,
                _nodes,
              );
              if (work.advance()) {
                _nodes.add(work.takeNode());
                _work = null;
              }
            }
          case _DecorationPhase.contexts:
            if (_index < _input!.geometry.nodes.length) {
              _appendContext(_input!.geometry.nodes[_index++]);
            } else {
              _phase = _DecorationPhase.publish;
            }
          case _DecorationPhase.publish:
            _result = ForumBodyRubyTreeDecorationBands._(
              _input!,
              _nodes,
              _contexts,
              _byNode,
            );
            _nodes = [];
            _contexts = [];
            _byNode = {};
            _phase = _DecorationPhase.ready;
          case _DecorationPhase.ready:
          case _DecorationPhase.transferred:
          case _DecorationPhase.closed:
            throw StateError('Ruby decoration preparation is retired');
        }
        parts++;
        _guard();
      }
      return parts;
    });
  }

  void _appendContext(ForumBodyRubyTreeNodePosition position) {
    final geometry = _input!.geometry, node = _nodes[position.id];
    final parent = position.parent == null
        ? null
        : _byNode[position.parent!.id]!;
    var over = parent?.baseAncestorOverEdge,
        under = parent?.baseAncestorUnderEdge;
    var row = parent?.physicalRow ?? (owner: position.id, rank: null);
    var baseline =
        parent?.physicalBaseline ??
        geometry.metrics.nodes[position.id].box!.alphabeticBaseline;
    final edge = position.edge;
    if (parent != null && edge != null) {
      if (edge.branch == ForumBodyRubyTreeBranch.base ||
          edge.branch == ForumBodyRubyTreeBranch.gap) {
        final p = parent.node, y = parent.position.origin.dy;
        over = _RubyDecorationEdges.min(
          over,
          p.localOverEdge == null ? null : y + p.localOverEdge!,
        );
        under = _RubyDecorationEdges.max(
          under,
          p.localUnderEdge == null ? null : y + p.localUnderEdge!,
        );
      }
      final original =
          geometry.metrics.input.sourceTree.nodes[parent.position.id];
      final rank = _decorationRank(original, edge);
      if (rank != null) {
        final numeric =
            geometry.metrics.nodes[parent.position.id]
                as ForumBodyRubyTreeContainerMetrics;
        final column = numeric.group ?? numeric.segment!.columns.first;
        row = (owner: parent.position.id, rank: rank);
        baseline =
            parent.position.contentOrigin.dy +
            column.annotations[rank].bandBaseline;
      }
    }
    final context = ForumBodyRubyTreeDecorationContext._(
      position: position,
      node: node,
      physicalRow: row,
      physicalBaseline: baseline,
      baseAncestorOverEdge: over,
      baseAncestorUnderEdge: under,
    );
    _contexts.add(context);
    _byNode[position.id] = context;
  }

  ForumBodyRubyTreeDecorationBands takeBands() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby decoration bands are incomplete');
    final result = _result!;
    _result = null;
    _phase = _DecorationPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby decoration preparation is reentrant');
    }
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
    if (_phase == _DecorationPhase.closed ||
        _phase == _DecorationPhase.transferred) {
      throw StateError('Ruby decoration preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _DecorationPhase.closed) {
      throw StateError('Ruby decoration owner is retired');
    }
  }

  void _drop() {
    _input = null;
    _ensureOwner = null;
    _work = null;
    _nodes = [];
    _contexts = [];
    _byNode = {};
  }

  void close() {
    if (_phase == _DecorationPhase.closed ||
        _phase == _DecorationPhase.transferred) {
      return;
    }
    _phase = _DecorationPhase.closed;
    _result = null;
    _drop();
  }
}

// Keep rank decoding shared by numeric aggregation and physical-row contexts.
int? _decorationRank(
  ForumBodyRubyTreeNode node,
  ForumBodyRubyTreeChildGeometry edge,
) => switch (edge.branch) {
  ForumBodyRubyTreeBranch.annotation => edge.index,
  ForumBodyRubyTreeBranch.span =>
    (node as ForumBodyRubyTreeSegment).spans[edge.index].rank,
  ForumBodyRubyTreeBranch.annotationGap =>
    (node as ForumBodyRubyTreeSegment)
        .spans[node.annotationGaps[edge.index].beforeSpan]
        .rank,
  ForumBodyRubyTreeBranch.fence =>
    (node as ForumBodyRubyTreeSegment).fences[edge.index].rank,
  _ => null,
};

final class _RubyDecorationEdges {
  static double? min(double? a, double? b) => a == null
      ? b
      : b == null
      ? a
      : math.min(a, b);
  static double? max(double? a, double? b) => a == null
      ? b
      : b == null
      ? a
      : math.max(a, b);
}

enum _DecorationNodePhase {
  marks,
  ranks,
  children,
  prefixes,
  emptyFonts,
  stack,
  finish,
}

final class _DecorationRow {
  _DecorationRow(this.original)
    : ascent = original.bandBaseline - original.bandTop,
      descent = original.bandBottom - original.bandBaseline,
      has = original.bandBottom > original.bandTop;
  final ForumBodyRubyAnnotationMetrics original;
  double ascent, descent;
  bool has, usesEmptyFont = false;
  void include(ForumBodyRubyChildMetrics box) {
    ascent = math.max(ascent, box.alphabeticBaseline - box.bounds.top);
    descent = math.max(descent, box.bounds.bottom - box.alphabeticBaseline);
    has = true;
  }

  bool get changed =>
      has != (original.bandBottom > original.bandTop) ||
      ascent != original.bandBaseline - original.bandTop ||
      descent != original.bandBottom - original.bandBaseline;
}

typedef _DecorationEmpty = ({
  int rank,
  ForumBodyRubyChildMetrics box,
  int start,
  int end,
});

final class _DecorationNodeWork {
  _DecorationNodeWork(this.input, this.id, this.previous)
    : original = input.geometry.metrics.input.sourceTree.nodes[id],
      numeric = input.geometry.metrics.nodes[id] {
    bounds = numeric.box?.bounds;
    final n = numeric;
    if (n is ForumBodyRubyTreeContainerMetrics) {
      container = n;
      column = n.group ?? n.segment?.columns.first;
      final c = column;
      if (c != null) {
        over = c.baseline - c.baseBandTop;
        under = c.baseBandBottom - c.baseline;
      }
    }
  }
  final ForumBodyRubyTreeEmphasisMetrics input;
  final int id;
  final List<ForumBodyRubyTreeDecorationNode> previous;
  final ForumBodyRubyTreeNode original;
  final ForumBodyRubyTreeNodeMetrics numeric;
  ForumBodyRubyTreeContainerMetrics? container;
  ForumBodyRubyGroupMetrics? column;
  Rect? bounds;
  var phase = _DecorationNodePhase.marks;
  int index = 0, targets = 0, baseTargets = 0;
  double over = 0, under = 0;
  bool changed = false;
  final rows = <_DecorationRow>[];
  final bands = <ForumBodyRubyTreeDecorationBand>[];
  final pending = <_DecorationEmpty>[];
  final baseMasks = <int, int>{}, gapMasks = <int, int>{};
  final baseOver = <int>[0],
      baseUnder = <int>[0],
      gapOver = <int>[0],
      gapUnder = <int>[0];
  double? localOver, localUnder;

  bool advance() {
    switch (phase) {
      case _DecorationNodePhase.marks:
        final source = input._bySource[id];
        if (source != null && index < source.line.marks.length) {
          final mark = source.line.marks[index++];
          final style = source
              .line
              .input
              .content
              .runs[source.line.input.units[mark.unitIndex].runIndex]
              .style;
          targets |= style.textEmphasis.side == ForumBodyEmphasisSide.over
              ? 1
              : 2;
        } else {
          index = 0;
          phase = _DecorationNodePhase.ranks;
        }
      case _DecorationNodePhase.ranks:
        if (index < (column?.annotations.length ?? 0)) {
          rows.add(_DecorationRow(column!.annotations[index++]));
        } else {
          index = 0;
          phase = _DecorationNodePhase.children;
        }
      case _DecorationNodePhase.children:
        final node = original;
        final count = node is ForumBodyRubyTreeContainer
            ? forumBodyRubyTreeChildSlotCount(node)
            : 0;
        if (index < count) {
          final edge = forumBodyRubyTreeChildGeometryAt(
            node as ForumBodyRubyTreeContainer,
            container!,
            index++,
          );
          if (edge != null) _includeChild(edge);
        } else {
          index = 0;
          phase = _DecorationNodePhase.prefixes;
        }
      case _DecorationNodePhase.prefixes:
        final node = original;
        if (pending.isNotEmpty &&
            node is ForumBodyRubyTreeSegment &&
            index < node.bases.length) {
          final b = baseMasks[index] ?? 0, g = gapMasks[index] ?? 0;
          baseOver.add(baseOver.last + (b & 1));
          baseUnder.add(baseUnder.last + ((b & 2) >> 1));
          gapOver.add(gapOver.last + (g & 1));
          gapUnder.add(gapUnder.last + ((g & 2) >> 1));
          index++;
        } else {
          index = 0;
          phase = _DecorationNodePhase.emptyFonts;
        }
      case _DecorationNodePhase.emptyFonts:
        if (index < pending.length) {
          final item = pending[index++], row = rows[item.rank];
          final side = row.original.side == ForumBodyRubySide.over ? 1 : 2;
          var relevant = baseTargets & side != 0;
          if (original is ForumBodyRubyTreeSegment) {
            final b = side == 1 ? baseOver : baseUnder,
                g = side == 1 ? gapOver : gapUnder;
            relevant =
                b[item.end] > b[item.start] ||
                (item.end > item.start + 1 && g[item.end] > g[item.start + 1]);
          }
          if (relevant) {
            row.include(item.box);
            row.usesEmptyFont = true;
            changed |= row.changed;
          }
        } else {
          index = 0;
          phase = _DecorationNodePhase.stack;
        }
      case _DecorationNodePhase.stack:
        if (index < rows.length) {
          _appendBand(index++);
        } else {
          phase = _DecorationNodePhase.finish;
        }
      case _DecorationNodePhase.finish:
        return true;
    }
    return false;
  }

  void _includeChild(ForumBodyRubyTreeChildGeometry edge) {
    final child = previous[edge.node], box = child.box;
    targets |= child._targets;
    if (box == null) return;
    final childChanged = !identical(
      box,
      input.geometry.metrics.nodes[edge.node].box,
    );
    if (!child.isFontOnly) {
      final shifted = box.bounds.shift(
        container!.frame.childOffset + edge.offset,
      );
      bounds = bounds!.expandToInclude(shifted);
      changed |= childChanged;
    }
    if (column == null) return;
    if (edge.branch == ForumBodyRubyTreeBranch.base ||
        edge.branch == ForumBodyRubyTreeBranch.gap) {
      baseTargets |= child._targets;
      if (original case final ForumBodyRubyTreeSegment node) {
        if (edge.branch == ForumBodyRubyTreeBranch.base) {
          baseMasks[edge.index] = child._targets;
        } else {
          final at = node.gaps[edge.index].beforeColumn;
          gapMasks[at] = (gapMasks[at] ?? 0) | child._targets;
        }
      }
      // The actual shared row already includes unchanged native children.
      // Re-subtracting positioned floats can spuriously add a fractional ulp.
      if (!childChanged) return;
      final nextOver = math.max(over, box.alphabeticBaseline - box.bounds.top),
          nextUnder = math.max(
            under,
            box.bounds.bottom - box.alphabeticBaseline,
          );
      changed |= nextOver != over || nextUnder != under;
      over = nextOver;
      under = nextUnder;
      return;
    }
    final rank = _decorationRank(original, edge);
    if (rank == null || edge.branch == ForumBodyRubyTreeBranch.fence) return;
    if (child.isFontOnly) {
      final span = original is ForumBodyRubyTreeSegment
          ? (original as ForumBodyRubyTreeSegment).spans[edge.index]
          : null;
      pending.add((
        rank: rank,
        box: box,
        start: span?.startColumn ?? 0,
        end: span?.endColumn ?? 1,
      ));
    } else if (childChanged) {
      rows[rank].include(box);
      changed |= rows[rank].changed;
    }
  }

  void _appendBand(int rank) {
    final row = rows[rank],
        actual = row.original,
        anchor = container!.frame.childOffset.dy + column!.baseline;
    final next = forumBodyAdvanceRubyBandStack(
      over: over,
      under: under,
      hasAnnotation: row.has,
      side: actual.side,
      ascent: row.ascent,
      descent: row.descent,
      gap: actual.gap,
    );
    over = next.over;
    under = next.under;
    final y = container!.frame.childOffset.dy;
    final band = ForumBodyRubyTreeDecorationBand._(
      rank: rank,
      side: actual.side,
      top: changed ? anchor + next.top : y + actual.bandTop,
      bottom: changed ? anchor + next.bottom : y + actual.bandBottom,
      baseline: changed ? anchor + next.baseline : y + actual.bandBaseline,
      usesEmptyFont: row.usesEmptyFont,
    );
    bands.add(band);
    if (band.isReserved) {
      if (band.side == ForumBodyRubySide.over) {
        localOver = _RubyDecorationEdges.min(localOver, band.top);
      } else {
        localUnder = _RubyDecorationEdges.max(localUnder, band.bottom);
      }
      final x = container!.frame.childOffset.dx,
          width =
              container!.group?.size.width ?? container!.segment!.size.width;
      bounds = bounds!.expandToInclude(
        Rect.fromLTRB(x, band.top, x + width, band.bottom),
      );
    }
  }

  ForumBodyRubyTreeDecorationNode takeNode() {
    final empty = input.emptyFonts._bySource[id];
    final fontOnly = numeric.box == null && empty != null;
    ForumBodyRubyChildMetrics? box = numeric.box;
    if (fontOnly) {
      box = ForumBodyRubyChildMetrics(
        bounds: empty.bounds,
        alphabeticBaseline: empty.alphabeticBaseline,
      );
    } else if (changed) {
      final b = bounds!;
      if (!b.isFinite ||
          !b.width.isFinite ||
          !b.height.isFinite ||
          b.width > 16384 ||
          b.height > 16384) {
        throw const ForumBodyEmphasisLineException(
          ForumBodyEmphasisLineFailure.geometry,
        );
      }
      box = ForumBodyRubyChildMetrics(
        bounds: b,
        alphabeticBaseline: numeric.box!.alphabeticBaseline,
      );
    }
    return ForumBodyRubyTreeDecorationNode._(
      id: id,
      box: box,
      isFontOnly: fontOnly,
      targets: targets,
      rows: bands,
      localOverEdge: localOver,
      localUnderEdge: localUnder,
    );
  }
}
