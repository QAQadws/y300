import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/domain/html_rendering/forum_html_render_input.dart';

abstract interface class ForumHtmlFragmentExtractor {
  ForumHtmlRenderInput extract({
    required String sourceId,
    required String rawHtml,
  });
}

class DefaultForumHtmlFragmentExtractor implements ForumHtmlFragmentExtractor {
  const DefaultForumHtmlFragmentExtractor();

  static const List<String> _contentSelectors = <String>[
    '.t_f',
    '.message',
    '.pcb',
    'article',
    'body',
  ];

  @override
  ForumHtmlRenderInput extract({
    required String sourceId,
    required String rawHtml,
  }) {
    final document = html_parser.parse(rawHtml);
    for (final node in document.querySelectorAll('script,noscript')) {
      node.remove();
    }

    final selected = _selectContentNode(document);
    final fragmentHtml = selected == null
        ? null
        : _withGlobalStyles(document: document, selected: selected).trim();

    return ForumHtmlRenderInput(
      sourceId: sourceId,
      rawHtml: rawHtml,
      fragmentHtml: fragmentHtml == null || fragmentHtml.isEmpty
          ? document.documentElement?.innerHtml.trim() ?? rawHtml.trim()
          : fragmentHtml,
    );
  }

  dom.Element? _selectContentNode(dom.Document document) {
    for (final selector in _contentSelectors) {
      final node = document.querySelector(selector);
      if (node != null) {
        return node;
      }
    }
    return null;
  }

  String _withGlobalStyles({
    required dom.Document document,
    required dom.Element selected,
  }) {
    if (selected.localName == 'body') {
      return selected.innerHtml;
    }
    final styles = document
        .querySelectorAll('style')
        .where((style) => !_isDescendantOf(style, selected))
        .map((style) => style.outerHtml)
        .join();
    return '$styles${selected.innerHtml}';
  }

  bool _isDescendantOf(dom.Node node, dom.Node ancestor) {
    dom.Node? current = node.parentNode;
    while (current != null) {
      if (identical(current, ancestor)) {
        return true;
      }
      current = current.parentNode;
    }
    return false;
  }
}
