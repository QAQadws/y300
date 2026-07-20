import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

/// Slices a prepared HTML fragment by readable-text rune offsets.
///
/// Element wrappers and zero-width structural nodes such as `<br>` are cloned
/// into the owning range, so every result remains independently parseable by
/// the final HTML renderer.
final class NovelReaderHtmlTextRangeSlicer {
  const NovelReaderHtmlTextRangeSlicer();

  String slice({required String html, required int start, required int end}) {
    if (start < 0 || end < start) {
      throw RangeError.range(start, 0, end, 'start');
    }
    final fragment = html_parser.parseFragment(html);
    final cursor = _TextCursor();
    final output = <html_dom.Node>[];
    for (final node in fragment.nodes) {
      final sliced = _sliceNode(node, start, end, cursor);
      if (sliced != null) {
        output.add(sliced);
      }
    }
    return output.map(_serializeNode).join();
  }

  html_dom.Node? _sliceNode(
    html_dom.Node node,
    int start,
    int end,
    _TextCursor cursor,
  ) {
    if (node is html_dom.Text) {
      final runes = node.data.runes.toList(growable: false);
      final nodeStart = cursor.value;
      cursor.value += runes.length;
      final from = (start - nodeStart).clamp(0, runes.length).toInt();
      final to = (end - nodeStart).clamp(0, runes.length).toInt();
      if (from >= to) {
        return null;
      }
      return html_dom.Text(String.fromCharCodes(runes.sublist(from, to)));
    }
    if (node is! html_dom.Element) {
      return null;
    }

    final clone = node.clone(false);
    for (final child in node.nodes) {
      final childLength = _textLength(child);
      if (childLength == 0) {
        if (cursor.value >= start && cursor.value < end) {
          clone.append(child.clone(true));
        }
        continue;
      }
      final childStart = cursor.value;
      final childEnd = childStart + childLength;
      if (childEnd <= start || childStart >= end) {
        cursor.value = childEnd;
        continue;
      }
      final sliced = _sliceNode(child, start, end, cursor);
      if (sliced != null) {
        clone.append(sliced);
      }
    }
    return clone.nodes.isEmpty ? null : clone;
  }

  int _textLength(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.data.runes.length;
    }
    return (node.text ?? '').runes.length;
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

final class _TextCursor {
  int value = 0;
}
