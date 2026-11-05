import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import 'forum_body_length.dart';
import 'forum_body_style_builder.dart';
import 'forum_body_style_inheritance.dart';
import 'forum_body_style_options.dart';
import 'forum_body_table_hints.dart';

typedef _StyleContext = ({
  ForumBodyResolvedStyle effective,
  ForumBodyResolvedStyle author,
  ForumBodyElementKind? kind,
  ForumBodyLength cellPadding,
});

/// Forward-only style traversal over existing IR. Consumers choose safe block
/// boundaries and yield/cancel using their reader session; this cursor owns no
/// timers, widgets, layout resources, full style map or reparsed HTML.
final class ForumBodyStyleCursor {
  ForumBodyStyleCursor({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
    ForumBodyCollapseLayout? collapses,
    ForumBodyElement? contentRoot,
  }) : identity = document.identity,
       fontRevision = reader.fontRevision,
       _collapses = collapses,
       _contentRoot = contentRoot,
       _builder = ForumBodyStyleBuilder(reader),
       _authorBuilder =
           reader.policy.values.values.contains(ForumBodyStyleScope.forceBody)
           ? ForumBodyStyleBuilder(reader, applyPolicy: false)
           : null,
       _inheritance = ForumBodyStyleInheritance(reader.policy) {
    if (collapses != null && !identical(collapses.document, document)) {
      throw ArgumentError('Collapse layout belongs to another document');
    }
    final initial = ForumBodyResolvedStyle(
      textStyle: reader.textStyle,
      role: ForumBodyTextRole.body,
      textAlign: reader.textAlign,
      textDirection: reader.textDirection,
      indent: forumBodyReaderIndent(reader, reader.textStyle.fontSize!),
      lineHeight: forumBodyReaderHeight(reader),
    );
    _StyleContext context = (
      effective: initial,
      author: initial,
      kind: null,
      cellPadding: const ForumBodyLength(1),
    );
    var nodes = document.nodes;
    if (contentRoot != null) {
      final ancestors = document.ancestryOf(contentRoot);
      if (ancestors == null) {
        throw ArgumentError('Content root belongs to another document');
      }
      var omitted = false;
      for (final ancestor in ancestors) {
        omitted |= collapses?.omitsBody(ancestor) ?? false;
        context = _resolve(ancestor, context);
      }
      _collectIssues();
      nodes = omitted || context.effective.hidden
          ? const []
          : contentRoot.children;
    }
    _root = context.effective;
    _frames.add((nodes: nodes.iterator, context: context));
  }
  final ForumBodyIdentity identity;
  final String fontRevision;
  late final ForumBodyResolvedStyle _root;
  final ForumBodyStyleBuilder _builder;
  final ForumBodyStyleBuilder? _authorBuilder;
  final ForumBodyStyleInheritance _inheritance;
  ForumBodyCollapseLayout? _collapses;
  ForumBodyElement? _contentRoot;
  final _frames = <({Iterator<ForumBodyNode> nodes, _StyleContext context})>[];
  final _pendingIssues = <ForumBodyStyleIssue>[];
  ForumBodyNode? _currentNode;
  ForumBodyResolvedStyle? _currentStyle;
  int _resolvedNodeCount = 0;
  bool _complete = false;
  bool _closed = false;
  bool _childrenPending = false;

  ForumBodyResolvedStyle get root => _root;
  ForumBodyElement? get contentRoot => _contentRoot;
  ForumBodyNode? get currentNode => _currentNode;
  ForumBodyResolvedStyle? get currentStyle => _currentStyle;
  int get resolvedNodeCount => _resolvedNodeCount;
  bool get isComplete => _complete;
  bool get isClosed => _closed;

  bool moveNext() {
    if (_closed) throw StateError('Style cursor is closed');
    try {
      return _moveNext();
    } catch (_) {
      close();
      rethrow;
    }
  }

  bool _moveNext() {
    _childrenPending = false;
    if (_complete) return false;
    while (_frames.isNotEmpty) {
      final frame = _frames.last;
      if (!frame.nodes.moveNext()) {
        _frames.removeLast();
        continue;
      }
      final node = frame.nodes.current;
      if (node is ForumBodyElement) {
        if (_collapses?.omitsBody(node) ?? false) continue;
        final context = _resolve(node, frame.context);
        _currentNode = node;
        _currentStyle = context.effective;
        _frames.add((nodes: node.children.iterator, context: context));
        _childrenPending = true;
        _collectIssues();
      } else {
        _currentNode = node;
        _currentStyle = frame.context.effective;
      }
      _resolvedNodeCount++;
      return true;
    }
    _complete = true;
    _currentNode = null;
    _currentStyle = null;
    return false;
  }

  /// Delegate the current element's descendants to a source-scoped consumer.
  /// This is only legal before any of those descendants have been visited.
  void skipChildren(ForumBodyElement element) {
    if (_closed || !_childrenPending || !identical(_currentNode, element)) {
      throw StateError('Style subtree has already advanced');
    }
    _frames.removeLast();
    _childrenPending = false;
  }

  _StyleContext _resolve(ForumBodyElement node, _StyleContext context) {
    final author =
        _authorBuilder?.resolve(
          node,
          context.author,
          parentKind: context.kind,
          cellPadding: context.cellPadding,
        ) ??
        context.author;
    final parent = _authorBuilder == null
        ? context.effective
        : _inheritance.parentFor(
            role: author.role,
            author: context.author,
            effective: context.effective,
          );
    return (
      effective: _builder.resolve(
        node,
        parent,
        parentKind: context.kind,
        cellPadding: context.cellPadding,
      ),
      author: author,
      kind: node.kind,
      cellPadding: node.kind == ForumBodyElementKind.table
          ? forumBodyTableCellPadding(node.attributes['cellpadding'])
          : context.cellPadding,
    );
  }

  void _collectIssues() {
    final author =
        _authorBuilder?.takeIssues() ?? const <ForumBodyStyleIssue>[];
    final effective = _builder.takeIssues();
    if (author.isEmpty && effective.length < 2) {
      _pendingIssues.addAll(effective);
      return;
    }
    final seen = <(String, String, String)>{};
    for (final issue in [...author, ...effective]) {
      if (seen.add((issue.path, issue.property, issue.value))) {
        _pendingIssues.add(issue);
      }
    }
  }

  /// Draining bounds accumulated diagnostics for a streaming consumer. Each
  /// immutable batch is independent of subsequent cursor progress or close.
  List<ForumBodyStyleIssue> takePendingIssues() {
    if (_closed) throw StateError('Style cursor is closed');
    if (_pendingIssues.isEmpty) return const [];
    final result = List<ForumBodyStyleIssue>.unmodifiable(_pendingIssues);
    _pendingIssues.clear();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _frames.clear();
    _collapses = null;
    _contentRoot = null;
    _currentNode = null;
    _currentStyle = null;
    _pendingIssues.clear();
    _builder.clear();
    _authorBuilder?.clear();
  }
}
