import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

/// An optional paint-only decoration of retained paragraphs or atomic blocks.
/// Keep the wrapper's layout and intrinsic sizes identical to [child]. Supply
/// it consistently for a body; changing its presence changes the render tree.
typedef ForumHtmlBlockDecorator =
    Widget Function(BuildContext context, Widget child);

// Internal grouping policy. Nested paragraphs in a table/quote/list move with
// that complete block, while structural outer divs do not merge all paragraphs.
abstract final class ForumHtmlBlockDecorationPolicy {
  static final _boxStyle = RegExp(
    r'(?:^|;)\s*(?:background(?:-[\w-]+)?|border(?:-[\w-]+)?|padding(?:-[\w-]+)?|overflow(?:-[\w-]+)?|transform|display|position)\s*:',
    caseSensitive: false,
  );
  static const _atomic = {
    'table',
    'blockquote',
    'pre',
    'ol',
    'ul',
    'figure',
    'img',
    'hr',
  };
  static const _paragraphs = {
    'p',
    'div',
    'section',
    'article',
    'center',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  };
  static const _descendants =
      'p,div,section,article,center,h1,h2,h3,h4,h5,h6,table,blockquote,pre,ol,ul,figure';

  static bool isAtomic(dom.Element element) =>
      _atomic.contains(element.localName) ||
      element.classes.contains('showcollapse') ||
      (_paragraphs.contains(element.localName) &&
          _boxStyle.hasMatch(element.attributes['style'] ?? ''));

  static bool hasAtomicAncestor(dom.Element element) {
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (isAtomic(parent)) return true;
    }
    return false;
  }

  static bool isBlock(dom.Element element) =>
      isAtomic(element) ||
      (_paragraphs.contains(element.localName) &&
          // A decorated ancestor must travel with its ink, not leave its box
          // behind while independently moving descendants through its clip.
          element.querySelector(_descendants) == null);

  static bool hasBlockAncestor(dom.Element element) {
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (isBlock(parent)) return true;
    }
    return false;
  }
}
