part of 'forum_body_inline_paragraph_view.dart';

/// One current member per unit, including missing ranks. Consuming source
/// windows uses the same pure cursor as synchronous resolveAtomicContexts.
final class _RubyBindingWork {
  _RubyBindingWork({
    required ForumBodyInlineSpanContent content,
    required int index,
    ForumBodyRubyGroupLayout? group,
    ForumBodyRubySegmentLayout? segment,
    ForumBodyRubySoftSpaceLayout? space,
    required void Function(ForumBodyTextLease) own,
  }) : _cursor = content.openAtomicContexts(index),
       _group = group,
       _segment = segment,
       _space = space,
       _members = segment?.inspectMembers(),
       _own = own;
  ForumBodyInlineAtomicContextCursor? _cursor;
  ForumBodyRubyGroupLayout? _group;
  ForumBodyRubySegmentLayout? _segment;
  ForumBodyRubySoftSpaceLayout? _space;
  ForumBodyRubySegmentMemberSnapshot? _members;
  void Function(ForumBodyTextLease)? _own;
  ForumBodyRubyGroupMemberSnapshot? _current;
  ForumBodyInlineContext? _base;
  List<ForumBodyInlineContext?> _annotations = [];
  List<_RubyColumnWindows> _columns = [];
  List<ForumBodyInlineContext?> _spans = [];
  List<ForumBodyInlineContext> _gaps = [];
  List<ForumBodyInlineContext> _annotationGaps = [];
  List<ForumBodyInlineContext> _spaceWindows = [];
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
      if (_space != null) {
        if (_spaceWindows.length < _space!.contents.length) {
          final lease = _space!.memberAt(_spaceWindows.length);
          _own!(lease);
          _spaceWindows.add(_cursor!.resolve(lease.content));
        } else {
          _cursor!.finish();
          _result = _RubySpaceBinding(
            _space!,
            UnmodifiableListView(_spaceWindows),
          );
        }
      } else if (_members != null &&
          _gaps.length < _members!.gaps.length &&
          _segment!.metrics.gaps[_gaps.length].input.beforeColumn == _column &&
          _rank < 0) {
        final member = _members!.gaps[_gaps.length].inspectMembers().base;
        _own!(member);
        _gaps.add(_cursor!.resolve(member.content));
      } else if (_column < (_members?.columns.length ?? 1)) {
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
      } else if (_members != null &&
          _annotationGaps.length < _members!.annotationGaps.length &&
          _segment!
                  .metrics
                  .annotationGaps[_annotationGaps.length]
                  .beforeSpanIndex ==
              _spans.length) {
        final gap = _members!.annotationGaps[_annotationGaps.length];
        _own!(gap.lease!);
        _annotationGaps.add(_cursor!.resolve(gap.content));
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
                UnmodifiableListView(_gaps),
                UnmodifiableListView(_annotationGaps),
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
    _space = null;
    _members = null;
    _current = null;
    _own = null;
    _base = null;
    _annotations = [];
    _columns = [];
    _spans = [];
    _gaps = [];
    _annotationGaps = [];
    _spaceWindows = [];
    _result = null;
  }
}
