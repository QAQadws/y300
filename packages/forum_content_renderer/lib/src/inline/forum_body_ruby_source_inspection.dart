part of 'forum_body_inline_source_preparation.dart';

/// Stop at the first actual nested or emphasized input. A flat ordinary root
/// keeps its existing split-column policy; no whole-list DFS hides in one part.
final class _RubySourceInspection {
  _RubySourceInspection(ForumBodyRubyGroupContent group)
    : _pending = [group.annotations.iterator, group.base.iterator],
      _gaps = group.annotationGaps.iterator,
      _complete = group.style.textEmphasis.isEnabled,
      emphasisKnown = group.style.textEmphasis.isEnabled;
  final List<Iterator<ForumBodyRubyInlineContent>> _pending;
  final Iterator<ForumBodyRubyRootAnnotationGap> _gaps;
  Iterator<ForumBodyResolvedStyle>? _styles;
  bool _complete, emphasisKnown;
  bool get isComplete => _complete;
  bool _nested = false;
  bool get needsTree => _nested || emphasisKnown;
  int advance({required int maxParts}) {
    var used = 0;
    while (!isComplete && used < maxParts) {
      if (_styles case final styles?) {
        if (!styles.moveNext()) {
          _styles = null;
        } else if (styles.current.textEmphasis.isEnabled) {
          emphasisKnown = _complete = true;
        }
      } else if (_pending.isNotEmpty) {
        final input = _pending.last;
        if (!input.moveNext()) {
          _pending.removeLast();
        } else {
          switch (input.current) {
            case ForumBodyRubyNestedContent():
              _nested = _complete = true;
            case ForumBodyRubyBaseContent(:final style, :final parts) ||
                ForumBodyRubyAnnotationContent(:final style, :final parts):
              if (style.textEmphasis.isEnabled) {
                emphasisKnown = _complete = true;
              } else {
                _pending.add(parts.iterator);
              }
            case ForumBodyRubyTextContent(:final content):
              _styles = _rubySourceStyles(content).iterator;
          }
        }
      } else if (_gaps.moveNext()) {
        _styles = _rubySourceStyles(_gaps.current.content).iterator;
      } else {
        _complete = true;
      }
      used++;
    }
    return used;
  }
}

Iterable<ForumBodyResolvedStyle> _rubySourceStyles(
  ForumBodyParagraphContent content,
) sync* {
  yield content.style;
  for (final run in content.runs) {
    yield run.style;
  }
}

/// Every original node/source/run produces a unit, including non-font nodes;
/// the iterator cannot skip an arbitrarily large text-only graph in one call.
Iterable<bool> _rubyTreeEmphasisFlags(ForumBodyRubyTreeInput tree) sync* {
  for (final node in tree.nodes) {
    yield node is ForumBodyRubyTreeContainer &&
        node.font.fontStrut.style.textEmphasis.isEnabled;
  }
  for (final source in tree.sources) {
    yield source.content.style.textEmphasis.isEnabled;
    for (final run in source.content.runs) {
      yield run.style.textEmphasis.isEnabled;
    }
  }
}
