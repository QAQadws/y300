import '../document/forum_body_document.dart';
import 'forum_body_styled_flow_cursor.dart';

/// Drops redundant blank-line events without altering retained source nodes.
/// One ordinary blank line remains between adjacent lines or paragraphs.
final class ForumBodyBlankLineFilter {
  String? _breakParent;
  int _breakCount = 0;
  ForumBodyElement? _blankParagraph;
  ForumBodyElement? _omittedParagraph;

  bool omit(ForumBodyStyledFlowCursor flow, ForumBodyStyledFlowEvent event) {
    final node = event.node;
    if (identical(node, _omittedParagraph)) {
      _omittedParagraph = null;
      return true;
    }
    final previousParagraph = _blankParagraph;
    if (previousParagraph != null &&
        (identical(node, previousParagraph) ||
            node.path.startsWith('${previousParagraph.path}/'))) {
      return false;
    }
    if (node is ForumBodyText && _isBlank(node.text)) {
      // Collapsible separators between discarded events would otherwise build
      // up in the same pending sequence across a long run of empty lines.
      return (_blankParagraph != null ||
              (_breakParent != null && _breakCount == 3)) &&
          flow.isOrdinaryProse;
    }
    if (node is ForumBodyElement &&
        node.kind == ForumBodyElementKind.hardBreak &&
        event.phase == ForumBodyFlowPhase.close) {
      return false;
    }
    if (node is ForumBodyElement &&
        event.phase == ForumBodyFlowPhase.open &&
        (node.kind == ForumBodyElementKind.hardBreak ||
            node.kind == ForumBodyElementKind.paragraph) &&
        node.attributes.isEmpty &&
        flow.isOrdinaryProse) {
      final parent = _parentPath(node);
      if (node.kind == ForumBodyElementKind.hardBreak) {
        _blankParagraph = null;
        if (_breakParent != parent) {
          _breakParent = parent;
          _breakCount = 0;
        }
        if (_breakCount < 3) _breakCount++;
        return _breakCount == 3;
      }
      if (_isBlankParagraph(node)) {
        _breakParent = null;
        _blankParagraph = node;
        if (previousParagraph != null &&
            _parentPath(previousParagraph) == parent) {
          flow.skipCurrentSubtree(event);
          _omittedParagraph = node;
          return true;
        }
        return false;
      }
    }
    _breakParent = null;
    _blankParagraph = null;
    return false;
  }

  static String _parentPath(ForumBodyElement node) {
    final separator = node.path.lastIndexOf('/');
    return separator < 0 ? '' : node.path.substring(0, separator);
  }

  static bool _isBlankParagraph(ForumBodyElement paragraph) {
    // Only short, plain spacer paragraphs are candidates. Inspecting one
    // event never walks a subtree or an unbounded whitespace prefix.
    if (paragraph.children.length > 8) return false;
    var hasVisibleSpace = false;
    for (final child in paragraph.children) {
      if (child is! ForumBodyText || !_isBlank(child.text, spacer: true)) {
        return false;
      }
      hasVisibleSpace |=
          child.text.contains('\u00a0') || child.text.contains('\u3000');
    }
    return hasVisibleSpace;
  }

  static bool _isBlank(String text, {bool spacer = false}) {
    if (text.length > 128) return false;
    return text.codeUnits.every(
      (unit) =>
          unit == 0x20 ||
          unit == 0x09 ||
          unit == 0x0a ||
          unit == 0x0c ||
          unit == 0x0d ||
          (spacer && (unit == 0xa0 || unit == 0x3000)),
    );
  }
}
