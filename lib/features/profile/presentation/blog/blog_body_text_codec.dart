import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Plain typing for new entries and the mobile site's text/line-break format.
/// Rich HTML stays in source mode; conversion must never discard its markup.
abstract final class BlogBodyTextCodec {
  static String encode(String text) =>
      text.split('\n').map(_encodeLine).join('<br>\n');

  static String _encodeLine(String text) {
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(text);
    // Discuz removes style attributes for ordinary accounts. Use supported
    // line breaks and spaces, not CSS white-space, to preserve plain input.
    return escaped.replaceAllMapped(RegExp(r' +'), (match) {
      final length = match.end - match.start;
      if (length == 1 && match.start > 0 && match.end < escaped.length) {
        return ' ';
      }
      return List.generate(
        length,
        (index) => index.isEven || index == length - 1 ? '&nbsp;' : ' ',
      ).join();
    });
  }

  static String? decode(String source) {
    final fragment = html.parseFragment(source);
    final text = StringBuffer();
    var afterBreak = false;
    for (final node in fragment.nodes) {
      if (node is dom.Text) {
        var value = node.text;
        // PHP nl2br keeps a source newline after each inserted <br>. It is
        // formatting whitespace in HTML, not a second visible blank line.
        if (afterBreak && value.startsWith('\n')) value = value.substring(1);
        text.write(value.replaceAll('\u00a0', ' '));
        afterBreak = false;
      } else if (node is dom.Element &&
          node.localName == 'br' &&
          node.attributes.isEmpty) {
        text.writeln();
        afterBreak = true;
      } else {
        return null;
      }
    }
    return text.toString();
  }
}
