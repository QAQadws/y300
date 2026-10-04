import 'package:html/dom.dart' as html_dom;

/// Local slicing coordinates count decoded text and inline BR, never widgets.
abstract final class NovelReaderDomSourceText {
  static String read(html_dom.Node node) {
    if (node is html_dom.Text) return node.data;
    if (node is html_dom.Element) {
      if (node.localName == 'br') return '\n';
      if (node.localName == 'script' || node.localName == 'style') return '';
    }
    return node.nodes.map(read).join();
  }
}
