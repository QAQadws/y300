import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// Display-only values; canonical HTML and reading coordinates stay unchanged.
final class NovelReaderScrollMarkupProjection {
  const NovelReaderScrollMarkupProjection._({
    required this.html,
    required this.fragments,
  });

  final String html;
  final List<String>? fragments;
}

/// Bounds the ordinary v1 `text<br>text` layout without guessing boundaries
/// inside styled elements, links, tables or collapse widgets. Pagination and
/// canonical HTML keep using the original document.
abstract final class NovelReaderScrollMarkup {
  static const int chunkCodeUnits = 1600;
  static const _chunkPrefix = '<y300-novel-text-chunk';
  static final _potentialBreak = RegExp(
    r'</?br(?=[\s/>])',
    caseSensitive: false,
  );

  /// Derives the markup and its ordered display fragments from one parsed tree.
  /// Existing marker input retains the compatibility entry point's spelling
  /// check, including short documents that prepare leaves byte-for-byte intact.
  static NovelReaderScrollMarkupProjection project(String html) {
    final prepared = _prepare(html);
    final fragments = prepared.html.contains(_chunkPrefix)
        ? _fragmentsFrom(
            prepared.fragment ?? parser.parseFragment(prepared.html),
          )
        : null;
    return NovelReaderScrollMarkupProjection._(
      html: prepared.html,
      fragments: fragments,
    );
  }

  /// Only split at our zero-margin block boundaries. Arbitrary HTML siblings
  /// can depend on margin collapsing or inline context and stay together.
  static List<String>? fragments(String prepared) {
    if (!prepared.contains(_chunkPrefix)) return null;
    return _fragmentsFrom(parser.parseFragment(prepared));
  }

  static List<String>? _fragmentsFrom(dom.DocumentFragment fragment) {
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

  static String prepare(String html) => _prepare(html).html;

  static ({String html, dom.DocumentFragment? fragment}) _prepare(String html) {
    // Without a possible BR no run can acquire a new boundary. End BR tags
    // count too: the HTML parser treats </br> as a line break.
    if (html.length < 12000 || !_potentialBreak.hasMatch(html)) {
      return (html: html, fragment: null);
    }
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
    if (!changed) return (html: html, fragment: fragment);
    final result = dom.DocumentFragment();
    for (final node in output) {
      result.append(node);
    }
    return (html: result.outerHtml, fragment: result);
  }
}
