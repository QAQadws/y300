import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

/// Slices a prepared HTML fragment by readable-text rune offsets.
///
/// Call [prepare] when several ranges belong to the same atom. The returned
/// session parses and indexes the fragment once, avoiding one full HTML parse
/// per generated page.
final class NovelReaderHtmlTextRangeSlicer {
  const NovelReaderHtmlTextRangeSlicer();

  NovelReaderHtmlTextRangeSliceSession prepare(String html) {
    return NovelReaderHtmlTextRangeSliceSession._(html);
  }

  String slice({required String html, required int start, required int end}) {
    return prepare(html).slice(start: start, end: end);
  }
}

/// Immutable, process-local index for one safe HTML atom.
final class NovelReaderHtmlTextRangeSliceSession {
  NovelReaderHtmlTextRangeSliceSession._(String html)
    : _nodes = _indexFragment(html);

  final List<_IndexedHtmlNode> _nodes;

  String slice({required int start, required int end}) {
    if (start < 0 || end < start) {
      throw RangeError.range(start, 0, end, 'start');
    }
    final output = <html_dom.Node>[];
    for (final node in _nodes) {
      final sliced = node.slice(start, end);
      if (sliced != null) {
        output.add(sliced);
      }
    }
    return output.map(_serializeNode).join();
  }

  static List<_IndexedHtmlNode> _indexFragment(String html) {
    final fragment = html_parser.parseFragment(html);
    final cursor = _TextCursor();
    return List<_IndexedHtmlNode>.unmodifiable(
      fragment.nodes.map((node) => _indexNode(node, cursor)),
    );
  }

  static _IndexedHtmlNode _indexNode(html_dom.Node node, _TextCursor cursor) {
    final start = cursor.value;
    if (node is html_dom.Text) {
      final runes = node.data.runes.toList(growable: false);
      cursor.value += runes.length;
      return _IndexedTextNode(
        original: node,
        start: start,
        end: cursor.value,
        runes: runes,
      );
    }
    if (node is html_dom.Element) {
      final children = node.nodes
          .map((child) => _indexNode(child, cursor))
          .toList(growable: false);
      return _IndexedElementNode(
        original: node,
        start: start,
        end: cursor.value,
        children: children,
      );
    }
    return _IndexedOpaqueNode(original: node, start: start, end: start);
  }
}

sealed class _IndexedHtmlNode {
  const _IndexedHtmlNode({
    required this.original,
    required this.start,
    required this.end,
  });

  final html_dom.Node original;
  final int start;
  final int end;

  bool ownedBy(int rangeStart, int rangeEnd) {
    return start == end
        ? start >= rangeStart && start < rangeEnd
        : end > rangeStart && start < rangeEnd;
  }

  html_dom.Node? slice(int rangeStart, int rangeEnd);
}

final class _IndexedTextNode extends _IndexedHtmlNode {
  const _IndexedTextNode({
    required super.original,
    required super.start,
    required super.end,
    required this.runes,
  });

  final List<int> runes;

  @override
  html_dom.Node? slice(int rangeStart, int rangeEnd) {
    final from = (rangeStart - start).clamp(0, runes.length).toInt();
    final to = (rangeEnd - start).clamp(0, runes.length).toInt();
    if (from >= to) {
      return null;
    }
    return html_dom.Text(String.fromCharCodes(runes.sublist(from, to)));
  }
}

final class _IndexedElementNode extends _IndexedHtmlNode {
  const _IndexedElementNode({
    required html_dom.Element super.original,
    required super.start,
    required super.end,
    required this.children,
  });

  final List<_IndexedHtmlNode> children;

  @override
  html_dom.Node? slice(int rangeStart, int rangeEnd) {
    if (!ownedBy(rangeStart, rangeEnd)) {
      return null;
    }
    if (start == end) {
      return original.clone(true);
    }
    final clone = original.clone(false) as html_dom.Element;
    for (final child in children) {
      final sliced = child.slice(rangeStart, rangeEnd);
      if (sliced != null) {
        clone.append(sliced);
      }
    }
    return clone.nodes.isEmpty ? null : clone;
  }
}

final class _IndexedOpaqueNode extends _IndexedHtmlNode {
  const _IndexedOpaqueNode({
    required super.original,
    required super.start,
    required super.end,
  });

  @override
  html_dom.Node? slice(int rangeStart, int rangeEnd) {
    return ownedBy(rangeStart, rangeEnd) ? original.clone(true) : null;
  }
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

final class _TextCursor {
  int value = 0;
}
