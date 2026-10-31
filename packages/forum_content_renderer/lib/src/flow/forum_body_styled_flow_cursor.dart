import '../document/forum_body_document.dart';
import '../style/forum_body_style_cursor.dart';
import '../style/forum_body_style_options.dart';
import '../style/forum_body_style_resolver.dart';

enum ForumBodyFlowPhase { open, text, close }

/// An ordered IR event, not an independently laid-out block or page coverage.
/// Open/close events refer to the same immutable element and resolved style;
/// text events refer to one original text node. Resources and hidden structures
/// remain explicit, so downstream format handlers cannot silently lose them.
final class ForumBodyStyledFlowEvent {
  const ForumBodyStyledFlowEvent._({
    required this.phase,
    required this.node,
    required this.style,
    required this.depth,
    required Object owner,
    required this.index,
  }) : _owner = owner;

  final ForumBodyFlowPhase phase;
  final ForumBodyNode node;
  final ForumBodyResolvedStyle style;
  final int depth;
  final int index;
  final Object _owner;
}

/// Forward-only structural consumption over the sole style cursor. At most one
/// following styled node is held to discover closures, plus active ancestry.
/// A batch may end inside a container: consumers retain their block state and
/// publish only genuinely stable layout boundaries. No HTML slice is produced.
final class ForumBodyStyledFlowCursor {
  ForumBodyStyledFlowCursor({
    required ForumBodyDocument document,
    required ForumBodyReaderStyle reader,
  }) : _styles = const ForumBodyStyleResolver().open(document, reader);

  final ForumBodyStyleCursor _styles;
  final _owner = Object();
  int _eventIndex = 0;
  final _open = <ForumBodyStyledFlowEvent>[];
  final _pendingIssues = <ForumBodyStyleIssue>[];
  ForumBodyNode? _nextNode;
  ForumBodyResolvedStyle? _nextStyle;
  List<ForumBodyStyleIssue> _nextIssues = const [];
  ForumBodyStyledFlowEvent? _current;
  bool _sourceEnded = false;
  bool _complete = false;
  bool _closed = false;

  ForumBodyIdentity get identity => _styles.identity;
  String get fontRevision => _styles.fontRevision;
  int get styleRevision => ForumBodyStyleResolver.revision;
  ForumBodyResolvedStyle get rootStyle => _styles.root;
  ForumBodyStyledFlowEvent? get current => _current;
  int get resolvedNodeCount => _styles.resolvedNodeCount;
  bool get isComplete => _complete;
  bool get isClosed => _closed;

  /// Provenance is a token, never a reference back to this cursor or a UI owner.
  bool owns(ForumBodyStyledFlowEvent event) => identical(event._owner, _owner);
  bool isOpenElement(ForumBodyStyledFlowEvent event) =>
      !_closed && _open.any((opened) => identical(opened, event));

  bool moveNext() {
    if (_closed) throw StateError('Styled flow cursor is closed');
    try {
      return _moveNext();
    } catch (_) {
      close();
      rethrow;
    }
  }

  bool _moveNext() {
    _current = null;
    if (_complete) return false;
    if (_nextNode == null && !_sourceEnded) {
      if (_styles.moveNext()) {
        _nextNode = _styles.currentNode!;
        _nextStyle = _styles.currentStyle!;
        _nextIssues = _styles.takePendingIssues();
      } else {
        _sourceEnded = true;
      }
    }
    final next = _nextNode;
    if (_open.isNotEmpty &&
        (next == null || !next.path.startsWith('${_open.last.node.path}/'))) {
      final opened = _open.removeLast();
      _current = ForumBodyStyledFlowEvent._(
        phase: ForumBodyFlowPhase.close,
        node: opened.node,
        style: opened.style,
        depth: opened.depth,
        owner: _owner,
        index: _eventIndex++,
      );
      return true;
    }
    if (next == null) {
      _complete = true;
      return false;
    }
    final event = ForumBodyStyledFlowEvent._(
      phase: next is ForumBodyText
          ? ForumBodyFlowPhase.text
          : ForumBodyFlowPhase.open,
      node: next,
      style: _nextStyle!,
      depth: _open.length,
      owner: _owner,
      index: _eventIndex++,
    );
    _nextNode = null;
    _nextStyle = null;
    _pendingIssues.addAll(_nextIssues);
    _nextIssues = const [];
    if (event.phase == ForumBodyFlowPhase.open) _open.add(event);
    _current = event;
    return true;
  }

  List<ForumBodyStyledFlowEvent> nextBatch({required int maxEvents}) {
    if (_closed) throw StateError('Styled flow cursor is closed');
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    final batch = <ForumBodyStyledFlowEvent>[];
    while (batch.length < maxEvents && moveNext()) {
      batch.add(_current!);
    }
    return List.unmodifiable(batch);
  }

  /// Diagnostics belong only to events already delivered, never lookahead.
  List<ForumBodyStyleIssue> takePendingIssues() {
    if (_closed) throw StateError('Styled flow cursor is closed');
    final result = List<ForumBodyStyleIssue>.unmodifiable(_pendingIssues);
    _pendingIssues.clear();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _styles.close();
    _open.clear();
    _pendingIssues.clear();
    _nextIssues = const [];
    _nextNode = null;
    _nextStyle = null;
    _current = null;
  }
}
