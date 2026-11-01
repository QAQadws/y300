import '../document/forum_body_document.dart';
import 'forum_body_style_builder.dart';
import 'forum_body_style_inheritance.dart';
import 'forum_body_style_options.dart';

/// Forward-only style traversal over existing IR. Consumers choose safe block
/// boundaries and yield/cancel using their reader session; this cursor owns no
/// timers, widgets, layout resources, full style map or reparsed HTML.
final class ForumBodyStyleCursor {
  ForumBodyStyleCursor({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
  }) : identity = document.identity,
       fontRevision = reader.fontRevision,
       root = ForumBodyResolvedStyle(
         textStyle: reader.textStyle,
         role: ForumBodyTextRole.body,
         textAlign: reader.textAlign,
         textDirection: reader.textDirection,
         indent: reader.firstLineIndent,
         lineHeight: forumBodyReaderHeight(reader),
       ),
       _builder = ForumBodyStyleBuilder(reader),
       _authorBuilder =
           reader.policy.values.values.contains(ForumBodyStyleScope.forceBody)
           ? ForumBodyStyleBuilder(reader, applyPolicy: false)
           : null,
       _inheritance = ForumBodyStyleInheritance(reader.policy) {
    _frames.add((
      nodes: document.nodes.iterator,
      parent: root,
      author: root,
      parentKind: null,
    ));
  }
  final ForumBodyIdentity identity;
  final String fontRevision;
  final ForumBodyResolvedStyle root;
  final ForumBodyStyleBuilder _builder;
  final ForumBodyStyleBuilder? _authorBuilder;
  final ForumBodyStyleInheritance _inheritance;
  final _frames =
      <
        ({
          Iterator<ForumBodyNode> nodes,
          ForumBodyResolvedStyle parent,
          ForumBodyResolvedStyle author,
          ForumBodyElementKind? parentKind,
        })
      >[];
  final _pendingIssues = <ForumBodyStyleIssue>[];
  ForumBodyNode? _currentNode;
  ForumBodyResolvedStyle? _currentStyle;
  int _resolvedNodeCount = 0;
  bool _complete = false;
  bool _closed = false;

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
    if (_complete) return false;
    while (_frames.isNotEmpty) {
      final frame = _frames.last;
      if (!frame.nodes.moveNext()) {
        _frames.removeLast();
        continue;
      }
      final node = frame.nodes.current;
      if (node is ForumBodyElement) {
        final author =
            _authorBuilder?.resolve(
              node,
              frame.author,
              parentKind: frame.parentKind,
            ) ??
            frame.author;
        final parent = _authorBuilder == null
            ? frame.parent
            : _inheritance.parentFor(
                role: author.role,
                author: frame.author,
                effective: frame.parent,
              );
        final style = _builder.resolve(
          node,
          parent,
          parentKind: frame.parentKind,
        );
        _currentNode = node;
        _currentStyle = style;
        _frames.add((
          nodes: node.children.iterator,
          parent: style,
          author: author,
          parentKind: node.kind,
        ));
        _collectIssues();
      } else {
        _currentNode = node;
        _currentStyle = frame.parent;
      }
      _resolvedNodeCount++;
      return true;
    }
    _complete = true;
    _currentNode = null;
    _currentStyle = null;
    return false;
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
    _currentNode = null;
    _currentStyle = null;
    _pendingIssues.clear();
    _builder.clear();
    _authorBuilder?.clear();
  }
}
