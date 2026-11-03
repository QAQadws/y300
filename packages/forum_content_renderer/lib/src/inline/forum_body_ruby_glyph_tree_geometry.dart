part of 'forum_body_ruby_tree_input.dart';

/// A source's actual tree context. Inline sources refer to an existing native
/// parent/window; its origin must not be treated as an independent glyph origin.
final class ForumBodyRubyGlyphTreeSourcePosition {
  const ForumBodyRubyGlyphTreeSourcePosition._(this.source, this.node);
  final ForumBodyRubyGlyphTreeSource source;
  final ForumBodyRubyTreeNodePosition node;
  bool get usesInlineParent => source.id < 0;
  Offset get contextOrigin =>
      usesInlineParent ? node.contentOrigin : node.origin;
}

/// Pure original-source positions and structural ancestry on the measured glyph
/// plane. The actual annotation bands remain in [metrics]; this is not marker
/// placement, a visible source binding, or complete rendered-source coverage.
final class ForumBodyRubyGlyphTreeGeometry {
  ForumBodyRubyGlyphTreeGeometry._(
    this.metrics,
    List<ForumBodyRubyTreeNodePosition> nodes,
    Map<int, ForumBodyRubyTreeNodePosition> byNode,
    List<ForumBodyRubyGlyphTreeSourcePosition> sources,
    Map<int, ForumBodyRubyGlyphTreeSourcePosition> bySource,
  ) : nodes = UnmodifiableListView(nodes),
      _byNode = UnmodifiableMapView(byNode),
      sources = UnmodifiableListView(sources),
      _bySource = UnmodifiableMapView(bySource);
  final ForumBodyRubyGlyphTreeMetrics metrics;

  /// Preorder traversal. Node IDs retain the original postorder namespace.
  final List<ForumBodyRubyTreeNodePosition> nodes;
  final Map<int, ForumBodyRubyTreeNodePosition> _byNode;

  /// The original source ordering, including empty RTs and inline contexts.
  final List<ForumBodyRubyGlyphTreeSourcePosition> sources;
  final Map<int, ForumBodyRubyGlyphTreeSourcePosition> _bySource;
  ForumBodyRubyTreeNodePosition nodeForId(int id) =>
      _byNode[id] ?? (throw ArgumentError.value(id, 'id'));
  ForumBodyRubyGlyphTreeSourcePosition sourceForId(int id) =>
      _bySource[id] ?? (throw ArgumentError.value(id, 'id'));
}

enum _GlyphGeometryPhase { nodes, sources, publish, ready, transferred, closed }

/// Enter a node, follow one edge/inline context, or publish one source per part.
/// Child offsets are shared with the existing visible tree, including spans,
/// RTL fences and the original enclosing frame. No native work is performed.
final class ForumBodyRubyGlyphTreeGeometryPreparation {
  ForumBodyRubyGlyphTreeGeometryPreparation({
    required ForumBodyRubyGlyphTreeMetrics metrics,
    required void Function() ensureOwner,
  }) : _metrics = metrics,
       _ensureOwner = ensureOwner {
    _stack.add(
      _GlyphPositionWork(
        _position(metrics.input._glyphTree.root, Offset.zero, null, null),
      ),
    );
  }
  ForumBodyRubyGlyphTreeMetrics? _metrics;
  void Function()? _ensureOwner;
  List<_GlyphPositionWork> _stack = [];
  List<ForumBodyRubyTreeNodePosition> _nodes = [];
  Map<int, ForumBodyRubyTreeNodePosition> _byNode = {};
  Map<int, ForumBodyRubyTreeNodePosition> _inlineSources = {};
  List<ForumBodyRubyGlyphTreeSourcePosition> _sources = [];
  Map<int, ForumBodyRubyGlyphTreeSourcePosition> _bySource = {};
  ForumBodyRubyGlyphTreeGeometry? _result;
  var _phase = _GlyphGeometryPhase.nodes;
  int _source = 0;
  bool _operating = false;
  bool get isReady => _phase == _GlyphGeometryPhase.ready;

  ForumBodyRubyTreeNodePosition _position(
    int id,
    Offset origin,
    ForumBodyRubyTreeNodePosition? parent,
    ForumBodyRubyTreeChildGeometry? edge,
  ) {
    final box = _metrics!.nodes[id];
    return ForumBodyRubyTreeNodePosition(
      id: id,
      origin: origin,
      contentOrigin: box is ForumBodyRubyTreeContainerMetrics
          ? origin + box.frame.childOffset
          : origin,
      parent: parent,
      edge: edge,
    );
  }

  int advance({int maxParts = 32}) => _operate(() {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    _guard();
    var parts = 0;
    while (!isReady && parts < maxParts) {
      switch (_phase) {
        case _GlyphGeometryPhase.nodes:
          if (_stack.isNotEmpty) {
            _advanceNode();
          } else {
            _phase = _GlyphGeometryPhase.sources;
          }
        case _GlyphGeometryPhase.sources:
          final input = _metrics!.input;
          if (_source < input.sources.length) {
            final source = input.sources[_source++];
            final position = source.id < 0
                ? _inlineSources[source.id]
                : _byNode[source.id];
            if (position == null) {
              throw StateError('Original source has no glyph-tree context');
            }
            final item = ForumBodyRubyGlyphTreeSourcePosition._(
              source,
              position,
            );
            _sources.add(item);
            _bySource[source.id] = item;
          } else {
            _phase = _GlyphGeometryPhase.publish;
          }
        case _GlyphGeometryPhase.publish:
          _result = ForumBodyRubyGlyphTreeGeometry._(
            _metrics!,
            _nodes,
            _byNode,
            _sources,
            _bySource,
          );
          _nodes = [];
          _byNode = {};
          _sources = [];
          _bySource = {};
          _phase = _GlyphGeometryPhase.ready;
        case _GlyphGeometryPhase.ready:
        case _GlyphGeometryPhase.transferred:
        case _GlyphGeometryPhase.closed:
          throw StateError('Ruby glyph geometry preparation is retired');
      }
      parts++;
      _guard();
    }
    return parts;
  });

  void _advanceNode() {
    final work = _stack.last, position = work.position;
    final node = _metrics!.input._glyphTree.nodes[position.id];
    if (!work.entered) {
      _nodes.add(position);
      _byNode[position.id] = position;
      work.entered = true;
    } else if (node is ForumBodyRubyTreeText) {
      _stack.removeLast();
    } else if (node is ForumBodyRubyTreeInline) {
      if (work.slot < node.sources.length) {
        _inlineSources[node.sources[work.slot++].id] = position;
      } else {
        _stack.removeLast();
      }
    } else {
      final container = node as ForumBodyRubyTreeContainer;
      if (work.slot < forumBodyRubyTreeChildSlotCount(container)) {
        final edge = forumBodyRubyTreeChildGeometryAt(
          container,
          _metrics!.nodes[position.id] as ForumBodyRubyTreeContainerMetrics,
          work.slot++,
        );
        if (edge != null) {
          _stack.add(
            _GlyphPositionWork(
              _position(
                edge.node,
                position.contentOrigin + edge.offset,
                position,
                edge,
              ),
            ),
          );
        }
      } else {
        _stack.removeLast();
      }
    }
  }

  ForumBodyRubyGlyphTreeGeometry takeGeometry() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby glyph geometry is incomplete');
    final result = _result!;
    _result = null;
    _phase = _GlyphGeometryPhase.transferred;
    _drop();
    return result;
  });

  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby glyph geometry preparation is reentrant');
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
    if (_phase == _GlyphGeometryPhase.closed ||
        _phase == _GlyphGeometryPhase.transferred) {
      throw StateError('Ruby glyph geometry preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _GlyphGeometryPhase.closed) {
      throw StateError('Ruby glyph geometry owner is retired');
    }
  }

  void _drop() {
    _metrics = null;
    _ensureOwner = null;
    _stack = [];
    _nodes = [];
    _byNode = {};
    _inlineSources = {};
    _sources = [];
    _bySource = {};
  }

  void close() {
    if (_phase == _GlyphGeometryPhase.closed ||
        _phase == _GlyphGeometryPhase.transferred) {
      return;
    }
    _phase = _GlyphGeometryPhase.closed;
    _result = null;
    _drop();
  }
}

final class _GlyphPositionWork {
  _GlyphPositionWork(this.position);
  final ForumBodyRubyTreeNodePosition position;
  bool entered = false;
  int slot = 0;
}
