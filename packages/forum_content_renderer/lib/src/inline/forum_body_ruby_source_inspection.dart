part of 'forum_body_inline_source_preparation.dart';

/// Inspect one authored part at a time for a nested base or annotation.
final class _RubySourceInspection {
  _RubySourceInspection(ForumBodyRubyGroupContent group)
    : _pending = [group.annotations.iterator, group.base.iterator];

  final List<Iterator<ForumBodyRubyInlineContent>> _pending;
  bool needsTree = false;
  bool get isComplete => needsTree || _pending.isEmpty;

  int advance({required int maxParts}) {
    var used = 0;
    while (!isComplete && used < maxParts) {
      final input = _pending.last;
      if (!input.moveNext()) {
        _pending.removeLast();
      } else {
        switch (input.current) {
          case ForumBodyRubyNestedContent():
            needsTree = true;
          case ForumBodyRubyBaseContent(:final parts) ||
              ForumBodyRubyAnnotationContent(:final parts):
            _pending.add(parts.iterator);
          case ForumBodyRubyTextContent():
            break;
        }
      }
      used++;
    }
    return used;
  }
}
