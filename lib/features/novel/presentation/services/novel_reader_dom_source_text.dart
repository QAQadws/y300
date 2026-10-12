import 'package:html/dom.dart' as html_dom;

/// Local slicing coordinates count decoded text and inline BR, never widgets.
abstract final class NovelReaderDomSourceText {
  static String read(html_dom.Node node) {
    if (node is html_dom.Text) return node.data;
    if (node is html_dom.Element) {
      if (node.localName == 'br') return '\n';
      if (node.localName == 'script' || node.localName == 'style') return '';
    }
    final buffer = StringBuffer();
    // Keep one child iterator per nesting level, without intermediate subtree
    // strings or a recursive call stack for deeply wrapped forum markup.
    final pending = <Iterator<html_dom.Node>>[node.nodes.iterator];
    while (pending.isNotEmpty) {
      final children = pending.last;
      if (!children.moveNext()) {
        pending.removeLast();
        continue;
      }
      final current = children.current;
      if (current is html_dom.Text) {
        buffer.write(current.data);
        continue;
      }
      if (current is html_dom.Element) {
        if (current.localName == 'br') {
          buffer.write('\n');
          continue;
        }
        if (current.localName == 'script' || current.localName == 'style') {
          continue;
        }
      }
      if (current.nodes.isNotEmpty) {
        pending.add(current.nodes.iterator);
      }
    }
    return buffer.toString();
  }
}
