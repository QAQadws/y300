part of 'forum_body_ruby_tree_input.dart';

/// One actual measured annotation row in original glyph-tree coordinates.
/// A shared row can reserve space without a local child. Zero-height empty
/// rows remain explicit: this value does not supply missing RT font metrics.
final class ForumBodyRubyGlyphTreeBand {
  const ForumBodyRubyGlyphTreeBand._({
    required this.rank,
    required this.side,
    required this.top,
    required this.bottom,
    required this.hasMeasuredAnnotation,
  });
  final int rank;
  final ForumBodyRubySide side;
  final double top, bottom;
  final bool hasMeasuredAnnotation;
  bool get isReserved => bottom > top;
}

/// Measured local rows and the limits inherited through actual base/gap
/// branches. RT/span branches retain earlier ancestors, but do not mistake
/// their own containing annotation row for an annotation on that RT's text.
final class ForumBodyRubyGlyphTreeBandContext {
  ForumBodyRubyGlyphTreeBandContext._({
    required this.position,
    required List<ForumBodyRubyGlyphTreeBand> localBands,
    required this.localOverEdge,
    required this.localUnderEdge,
    required this.baseAncestorOverEdge,
    required this.baseAncestorUnderEdge,
  }) : localBands = UnmodifiableListView(localBands);
  final ForumBodyRubyTreeNodePosition position;
  final List<ForumBodyRubyGlyphTreeBand> localBands;
  final double? localOverEdge, localUnderEdge;
  final double? baseAncestorOverEdge, baseAncestorUnderEdge;
}

/// Source-bound numeric inputs for later decoration placement. This is NOT a
/// complete emphasis format: empty/auto-hidden RT font reservation, marker
/// fonts, sibling-row alignment, visible binding and coverage remain separate.
final class ForumBodyRubyGlyphTreeBands {
  ForumBodyRubyGlyphTreeBands._(
    this.geometry,
    List<ForumBodyRubyGlyphTreeBandContext> contexts,
    Map<int, ForumBodyRubyGlyphTreeBandContext> byNode,
  ) : contexts = UnmodifiableListView(contexts),
      _byNode = UnmodifiableMapView(byNode);
  final ForumBodyRubyGlyphTreeGeometry geometry;
  final List<ForumBodyRubyGlyphTreeBandContext> contexts;
  final Map<int, ForumBodyRubyGlyphTreeBandContext> _byNode;
  ForumBodyRubyGlyphTreeBandContext nodeForId(int id) =>
      _byNode[id] ?? (throw ArgumentError.value(id, 'id'));

  /// For a negative source ID, returns its real native parent context, never
  /// an inferred position/band for text inside that opaque inline format.
  ForumBodyRubyGlyphTreeBandContext sourceForId(int id) =>
      nodeForId(geometry.sourceForId(id).node.id);
}

enum _GlyphBandsPhase { node, ranks, publish, ready, transferred, closed }

/// One node or measured row per part. Parent summaries already exist in the
/// geometry's preorder, so a deep leaf never scans/copies all its ancestors.
final class ForumBodyRubyGlyphTreeBandsPreparation {
  ForumBodyRubyGlyphTreeBandsPreparation({
    required ForumBodyRubyGlyphTreeGeometry geometry,
    required void Function() ensureOwner,
  }) : _geometry = geometry,
       _ensureOwner = ensureOwner;
  ForumBodyRubyGlyphTreeGeometry? _geometry;
  void Function()? _ensureOwner;
  List<ForumBodyRubyGlyphTreeBandContext> _contexts = [];
  Map<int, ForumBodyRubyGlyphTreeBandContext> _byNode = {};
  List<ForumBodyRubyGlyphTreeBand> _bands = [];
  double? _localOver, _localUnder, _ancestorOver, _ancestorUnder;
  int _index = 0, _rank = 0;
  var _phase = _GlyphBandsPhase.node;
  ForumBodyRubyGlyphTreeBands? _result;
  bool _operating = false;
  bool get isReady => _phase == _GlyphBandsPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      var parts = 0;
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _GlyphBandsPhase.node:
            if (_index == _geometry!.nodes.length) {
              _phase = _GlyphBandsPhase.publish;
            } else {
              final node = _geometry!.nodes[_index];
              final parent = node.parent == null
                  ? null
                  : _byNode[node.parent!.id]!;
              _ancestorOver = parent?.baseAncestorOverEdge;
              _ancestorUnder = parent?.baseAncestorUnderEdge;
              final branch = node.edge?.branch;
              if (branch == ForumBodyRubyTreeBranch.base ||
                  branch == ForumBodyRubyTreeBranch.gap) {
                _ancestorOver = _minEdge(_ancestorOver, parent!.localOverEdge);
                _ancestorUnder = _maxEdge(
                  _ancestorUnder,
                  parent.localUnderEdge,
                );
              }
              _phase = _GlyphBandsPhase.ranks;
            }
          case _GlyphBandsPhase.ranks:
            final position = _geometry!.nodes[_index];
            final numeric = _geometry!.metrics.nodes[position.id];
            final container = numeric is ForumBodyRubyTreeContainerMetrics
                ? numeric
                : null;
            // Segment columns have the same actual shared row coordinates.
            // Presence belongs to the union, not to the first column's glyphs.
            final column =
                container?.group ?? container?.segment?.columns.first;
            if (_rank < (column?.annotations.length ?? 0)) {
              final rank = _rank++, row = column!.annotations[rank];
              final band = ForumBodyRubyGlyphTreeBand._(
                rank: rank,
                side: row.side,
                top: position.contentOrigin.dy + row.bandTop,
                bottom: position.contentOrigin.dy + row.bandBottom,
                hasMeasuredAnnotation:
                    container!.segment?.level.annotations[rank].hasAnnotation ??
                    row.hasAnnotation,
              );
              _bands.add(band);
              if (band.isReserved) {
                if (band.side == ForumBodyRubySide.over) {
                  _localOver = _minEdge(_localOver, band.top);
                } else {
                  _localUnder = _maxEdge(_localUnder, band.bottom);
                }
              }
            } else {
              final context = ForumBodyRubyGlyphTreeBandContext._(
                position: position,
                localBands: _bands,
                localOverEdge: _localOver,
                localUnderEdge: _localUnder,
                baseAncestorOverEdge: _ancestorOver,
                baseAncestorUnderEdge: _ancestorUnder,
              );
              _contexts.add(context);
              _byNode[position.id] = context;
              _bands = [];
              _localOver = _localUnder = null;
              _rank = 0;
              _index++;
              _phase = _GlyphBandsPhase.node;
            }
          case _GlyphBandsPhase.publish:
            _result = ForumBodyRubyGlyphTreeBands._(
              _geometry!,
              _contexts,
              _byNode,
            );
            _contexts = [];
            _byNode = {};
            _phase = _GlyphBandsPhase.ready;
          case _GlyphBandsPhase.ready:
          case _GlyphBandsPhase.transferred:
          case _GlyphBandsPhase.closed:
            throw StateError('Ruby glyph band preparation is retired');
        }
        parts++;
        _guard();
      }
      return parts;
    });
  }

  ForumBodyRubyGlyphTreeBands takeBands() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby glyph bands are incomplete');
    final result = _result!;
    _result = null;
    _phase = _GlyphBandsPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby glyph band preparation is reentrant');
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
    if (_phase == _GlyphBandsPhase.closed ||
        _phase == _GlyphBandsPhase.transferred) {
      throw StateError('Ruby glyph band preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _GlyphBandsPhase.closed) {
      throw StateError('Ruby glyph band owner is retired');
    }
  }

  void _drop() {
    _geometry = null;
    _ensureOwner = null;
    _contexts = [];
    _byNode = {};
    _bands = [];
  }

  void close() {
    if (_phase == _GlyphBandsPhase.closed ||
        _phase == _GlyphBandsPhase.transferred) {
      return;
    }
    _phase = _GlyphBandsPhase.closed;
    _result = null;
    _drop();
  }

  static double? _minEdge(double? a, double? b) => a == null
      ? b
      : b == null
      ? a
      : a < b
      ? a
      : b;
  static double? _maxEdge(double? a, double? b) => a == null
      ? b
      : b == null
      ? a
      : a > b
      ? a
      : b;
}
