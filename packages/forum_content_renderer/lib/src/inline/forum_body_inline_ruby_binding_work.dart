part of 'forum_body_inline_paragraph_view.dart';

/// One current member per unit, including missing ranks. Consuming source
/// windows uses the same pure cursor as synchronous resolveAtomicContexts.
final class _RubyBindingWork {
  _RubyBindingWork({
    required ForumBodyInlineSpanContent content,
    required int index,
    ForumBodyRubyGroupLayout? group,
    ForumBodyRubySegmentLayout? segment,
    required void Function(ForumBodyTextLease) own,
  }) : _cursor = content.openAtomicContexts(index),
       _group = group,
       _segment = segment,
       _members = segment?.inspectMembers(),
       _own = own;
  ForumBodyInlineAtomicContextCursor? _cursor;
  ForumBodyRubyGroupLayout? _group;
  ForumBodyRubySegmentLayout? _segment;
  ForumBodyRubySegmentMemberSnapshot? _members;
  void Function(ForumBodyTextLease)? _own;
  ForumBodyRubyGroupMemberSnapshot? _current;
  ForumBodyInlineContext? _base;
  List<ForumBodyInlineContext?> _annotations = [];
  List<_RubyColumnWindows> _columns = [];
  List<ForumBodyInlineContext?> _spans = [];
  _RubyBinding? _result;
  var _column = 0;
  var _rank = -1;
  var _closed = false;
  bool get isComplete => _result != null;

  int advance({required int maxParts}) {
    if (_closed || isComplete) throw StateError('Ruby binding is not active');
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    var work = 0;
    while (work < maxParts && !isComplete) {
      if (_column < (_members?.columns.length ?? 1)) {
        if (_rank < 0) {
          _current = (_members?.columns[_column] ?? _group!).inspectMembers();
          _own!(_current!.base);
          _base = _cursor!.resolve(_current!.base.content);
          _rank = 0;
        } else {
          final item = _current!.annotations[_rank++];
          if (item.lease != null) _own!(item.lease!);
          _annotations.add(
            item.lease == null ? null : _cursor!.resolve(item.content),
          );
        }
        if (_rank == _current!.annotations.length) {
          _columns.add(
            _RubyColumnWindows(_base!, UnmodifiableListView(_annotations)),
          );
          _annotations = [];
          _base = null;
          _current = null;
          _column++;
          _rank = -1;
        }
      } else if (_spans.length < (_members?.spans.length ?? 0)) {
        final span = _members!.spans[_spans.length];
        if (span.lease != null) _own!(span.lease!);
        _spans.add(span.lease == null ? null : _cursor!.resolve(span.content));
      } else {
        _cursor!.finish();
        _result = _segment == null
            ? _RubyColumnBinding(_group!, _columns.single)
            : _RubySegmentBinding(
                _segment!,
                UnmodifiableListView(_columns),
                UnmodifiableListView(_spans),
              );
      }
      work++;
    }
    return work;
  }

  _RubyBinding takeBinding() {
    if (_closed || !isComplete) throw StateError('Ruby binding is incomplete');
    final result = _result!;
    _result = null;
    close();
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _cursor?.close();
    _cursor = null;
    _group = null;
    _segment = null;
    _members = null;
    _current = null;
    _own = null;
    _base = null;
    _annotations = [];
    _columns = [];
    _spans = [];
    _result = null;
  }
}
