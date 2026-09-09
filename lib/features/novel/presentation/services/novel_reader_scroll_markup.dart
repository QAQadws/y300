import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// Bounds the ordinary v1 `text<br>text` layout without guessing boundaries
/// inside styled elements, links, tables or collapse widgets. Pagination and
/// canonical HTML keep using the original document.
abstract final class NovelReaderScrollMarkup {
  static const int chunkCodeUnits = 1600;

  /// Only split at our zero-margin block boundaries. Arbitrary HTML siblings
  /// can depend on margin collapsing or inline context and stay together.
  static List<String>? fragments(String prepared) {
    if (!prepared.contains('<y300-novel-text-chunk')) return null;
    final fragment = parser.parseFragment(prepared);
    final result = <String>[];
    var pending = dom.DocumentFragment();
    for (final node in fragment.nodes.toList(growable: false)) {
      pending.append(node);
      if (node is dom.Element && node.localName == 'y300-novel-text-chunk') {
        result.add(pending.outerHtml);
        pending = dom.DocumentFragment();
      }
    }
    if (result.length < 2) return null;
    // Keep the trailing inline/collapse context attached to its last block.
    result[result.length - 1] += pending.outerHtml;
    return List.unmodifiable(result);
  }

  static String prepare(String html) {
    if (html.length < 12000) return html;
    final fragment = parser.parseFragment(html);
    final output = <dom.Node>[];
    final run = <dom.Node>[];
    var changed = false;

    void flush() {
      var cost = 0;
      var start = 0;
      final chunks = <List<dom.Node>>[];
      for (var index = 0; index < run.length - 1; index++) {
        final node = run[index];
        cost += node.text?.length ?? 0;
        if (cost >= chunkCodeUnits &&
            node is dom.Element &&
            node.localName == 'br') {
          // A block boundary replaces exactly this one explicit line break.
          chunks.add(run.sublist(start, index));
          start = index + 1;
          cost = 0;
        }
      }
      if (chunks.isEmpty) {
        output.addAll(run);
      } else {
        chunks.add(run.sublist(start));
        for (final nodes in chunks) {
          final block = dom.Element.tag('y300-novel-text-chunk')
            ..attributes['style'] = 'display:block;margin:0';
          for (final node in nodes) {
            block.append(node);
          }
          output.add(block);
        }
        changed = true;
      }
      run.clear();
    }

    for (final node in fragment.nodes.toList(growable: false)) {
      if (node is dom.Text ||
          (node is dom.Element &&
              node.localName == 'br' &&
              node.attributes.isEmpty)) {
        run.add(node);
      } else {
        flush();
        output.add(node);
      }
    }
    flush();
    if (!changed) return html;
    final result = dom.DocumentFragment();
    for (final node in output) {
      result.append(node);
    }
    return result.outerHtml;
  }
}
