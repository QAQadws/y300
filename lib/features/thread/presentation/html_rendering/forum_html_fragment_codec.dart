import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

abstract interface class ForumHtmlFragmentCodec {
  html_dom.DocumentFragment parse(String html);

  String serialize(html_dom.DocumentFragment fragment);
}

final class HtmlPackageForumHtmlFragmentCodec
    implements ForumHtmlFragmentCodec {
  const HtmlPackageForumHtmlFragmentCodec();

  @override
  html_dom.DocumentFragment parse(String html) {
    return html_parser.parseFragment(html);
  }

  @override
  String serialize(html_dom.DocumentFragment fragment) {
    return fragment.nodes.map(_serializeNode).join();
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }
}
