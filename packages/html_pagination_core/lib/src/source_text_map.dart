import 'package:html/dom.dart' as dom;

import 'dom_text_index.dart';
import 'ports.dart';

/// Read-only source coordinates for one node in a repaired HTML fragment.
/// Neither byte offsets in HTML nor application semantic positions.
final class HtmlSourceTextRange {
  const HtmlSourceTextRange({
    required this.runeStart,
    required this.runeEnd,
    required this.graphemeStart,
    required this.graphemeEnd,
  });

  final int runeStart;
  final int runeEnd;
  final int graphemeStart;
  final int graphemeEnd;

  int get runeLength => runeEnd - runeStart;
}

/// Projects the existing DOM index without retaining a DOM or slice session.
///
/// Paths use child-node indexes (including comments), e.g. `0/2/1`. They are
/// meaningful only for the exact parsed fragment/content identity. BR counts
/// as one source rune, widgets as zero; adjacent styled text shares grapheme
/// segmentation. An injected parser can return its already parsed fragment.
final class HtmlSourceTextMap {
  HtmlSourceTextMap._(this.runeLength, this.rangesByPath, this._boundaries);

  factory HtmlSourceTextMap.parse(
    String html, {
    HtmlFragmentParser fragmentParser = const DefaultHtmlFragmentParser(),
    HtmlProtectedInlinePredicate? protectedInlinePredicate,
  }) {
    final index = HtmlDomTextIndex.parse(
      html,
      fragmentParser: fragmentParser,
      protectedInlinePredicate: protectedInlinePredicate ?? _notProtected,
    );
    final ranges = <String, HtmlSourceTextRange>{};
    void visit(List<HtmlDomIndexedNode> nodes, String prefix) {
      for (var i = 0; i < nodes.length; i++) {
        final path = prefix.isEmpty ? '$i' : '$prefix/$i';
        final node = nodes[i];
        ranges[path] = HtmlSourceTextRange(
          runeStart: node.runeStart,
          runeEnd: node.runeEnd,
          graphemeStart: node.graphemeStart,
          graphemeEnd: node.graphemeEnd,
        );
        if (node is HtmlDomIndexedElementNode) visit(node.children, path);
      }
    }

    visit(index.roots, '');
    return HtmlSourceTextMap._(
      index.runeLength,
      Map.unmodifiable(ranges),
      List.unmodifiable([
        for (var i = 0; i <= index.graphemeLength; i++)
          index.sourceRuneAtGraphemeBoundary(i),
      ]),
    );
  }

  final int runeLength;
  final Map<String, HtmlSourceTextRange> rangesByPath;
  final List<int> _boundaries;

  int get graphemeLength => _boundaries.length - 1;

  int sourceRuneAtGraphemeBoundary(int offset) {
    RangeError.checkValueInInterval(offset, 0, graphemeLength, 'offset');
    return _boundaries[offset];
  }

  static bool _notProtected(dom.Element _) => false;
}
