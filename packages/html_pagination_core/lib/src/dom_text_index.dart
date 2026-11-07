import 'dart:convert';
import 'package:html/dom.dart' as html_dom;
import 'package:forum_content_renderer/forum_text.dart';
export 'package:forum_content_renderer/forum_text.dart'
    show
        HtmlSourceDomIndex,
        HtmlDomProtectedNodeKind,
        HtmlDomGrapheme,
        HtmlDomIndexedNode,
        HtmlDomIndexedTextNode,
        HtmlDomIndexedElementNode,
        HtmlDomIndexedOpaqueNode;

final class HtmlDomTextSlice {
  const HtmlDomTextSlice({
    required this.html,
    required this.hasRenderableContent,
    required this.domNodeCount,
  });

  final String html;
  final bool hasRenderableContent;

  /// Retained element, text and opaque nodes, excluding the fragment root.
  final int domNodeCount;
}

/// Legacy DOM slicing over the renderer-owned source index.
final class HtmlDomTextIndex {
  HtmlDomTextIndex._(this._source, this._protectedInlinePredicate);
  factory HtmlDomTextIndex.parse(
    String html, {
    HtmlFragmentParser fragmentParser = const DefaultHtmlFragmentParser(),
    HtmlProtectedInlinePredicate protectedInlinePredicate = _notProtectedInline,
  }) => HtmlDomTextIndex._(
    HtmlSourceDomIndex.parse(
      html,
      fragmentParser: fragmentParser,
      protectedInlinePredicate: protectedInlinePredicate,
    ),
    protectedInlinePredicate,
  );

  final HtmlSourceDomIndex _source;
  final HtmlProtectedInlinePredicate _protectedInlinePredicate;
  List<HtmlDomIndexedNode> get roots => _source.roots;
  List<HtmlDomGrapheme> get graphemes => _source.graphemes;
  int get runeLength => _source.runeLength;
  int get graphemeLength => _source.graphemeLength;
  int sourceRuneAtGraphemeBoundary(int offset) =>
      _source.sourceRuneAtGraphemeBoundary(offset);

  HtmlDomTextSlice sliceRunes({required int start, required int end}) {
    _validateRange(start: start, end: end, length: runeLength);
    final nodes = roots
        .map((node) => _sliceRunes(node, start, end))
        .whereType<html_dom.Node>()
        .toList(growable: false);
    return _result(nodes);
  }

  HtmlDomTextSlice sliceGraphemes({required int start, required int end}) {
    _validateRange(start: start, end: end, length: graphemeLength);
    final nodes = roots
        .map((node) => _sliceGraphemes(node, start, end))
        .whereType<html_dom.Node>()
        .toList(growable: false);
    return _result(nodes);
  }

  HtmlDomTextSlice _result(List<html_dom.Node> nodes) {
    return HtmlDomTextSlice(
      html: nodes.map(_serializeNode).join(),
      hasRenderableContent: nodes.any(
        (node) => _hasRenderableContent(node, _protectedInlinePredicate),
      ),
      domNodeCount: _countNodes(nodes),
    );
  }

  static int _countNodes(List<html_dom.Node> roots) {
    // Count the already sliced tree, including complete protected/opaque
    // clones. Re-parsing serialized HTML would add work to every fit probe.
    final pending = <html_dom.Node>[...roots];
    var count = 0;
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      count += 1;
      pending.addAll(node.nodes);
    }
    return count;
  }

  static HtmlDomProtectedNodeKind? _protectedKind(
    html_dom.Element element,
    HtmlProtectedInlinePredicate protectedInlinePredicate,
  ) {
    if (element.localName?.toLowerCase() == 'ruby') {
      return HtmlDomProtectedNodeKind.ruby;
    }
    if (protectedInlinePredicate(element)) {
      return HtmlDomProtectedNodeKind.inlineWidget;
    }
    return null;
  }

  static void _validateRange({
    required int start,
    required int end,
    required int length,
  }) {
    if (start < 0 || end < start || end > length) {
      throw RangeError('Invalid HTML text range [$start, $end) for $length.');
    }
  }

  static bool _hasRenderableContent(
    html_dom.Node node,
    HtmlProtectedInlinePredicate protectedInlinePredicate,
  ) {
    if (node is html_dom.Text) {
      return _renderableTextPattern.hasMatch(node.data);
    }
    if (node is! html_dom.Element) {
      return false;
    }
    if (_protectedKind(node, protectedInlinePredicate) != null ||
        const <String>{
          'hr',
          'img',
          'iframe',
          'object',
          'video',
          'audio',
        }.contains(node.localName?.toLowerCase())) {
      return true;
    }
    return node.nodes.any(
      (child) => _hasRenderableContent(child, protectedInlinePredicate),
    );
  }

  static String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) return node.outerHtml;
    if (node is html_dom.Text) return const HtmlEscape().convert(node.data);
    return node.text ?? '';
  }

  static final _renderableTextPattern = RegExp(
    r'[^\s\u00A0\u200B\u2060\u3000\uFEFF]',
  );
  html_dom.Node? _sliceRunes(HtmlDomIndexedNode node, int start, int end) {
    if (node is HtmlDomIndexedTextNode) {
      final from = (start - node.runeStart).clamp(0, node.runes.length).toInt();
      final to = (end - node.runeStart).clamp(0, node.runes.length).toInt();
      return from >= to
          ? null
          : html_dom.Text(String.fromCharCodes(node.runes.sublist(from, to)));
    }
    if (!node.ownsRuneRange(start, end)) return null;
    if (node is! HtmlDomIndexedElementNode ||
        node.tagName == 'br' ||
        node.runeStart == node.runeEnd) {
      return node.original.clone(true);
    }
    return _sliceChildren(node, (child) => _sliceRunes(child, start, end));
  }

  html_dom.Node? _sliceGraphemes(HtmlDomIndexedNode node, int start, int end) {
    if (node is HtmlDomIndexedTextNode) {
      // A grapheme can span styled nodes; retain the single shared boundary map.
      return _sliceRunes(
        node,
        sourceRuneAtGraphemeBoundary(start),
        sourceRuneAtGraphemeBoundary(end),
      );
    }
    if (!node.ownsGraphemeRange(start, end)) return null;
    if (node is! HtmlDomIndexedElementNode) return node.original.clone(true);
    if (node.protectedKind != null || node.tagName == 'br') {
      return start <= node.graphemeStart && end >= node.graphemeEnd
          ? node.original.clone(true)
          : null;
    }
    if (node.graphemeStart == node.graphemeEnd) {
      return node.original.clone(true);
    }
    return _sliceChildren(node, (child) => _sliceGraphemes(child, start, end));
  }

  html_dom.Node? _sliceChildren(
    HtmlDomIndexedElementNode node,
    html_dom.Node? Function(HtmlDomIndexedNode) slice,
  ) {
    final clone = node.original.clone(false) as html_dom.Element;
    for (final child in node.children) {
      final sliced = slice(child);
      if (sliced != null) clone.append(sliced);
    }
    return clone.nodes.isEmpty ? null : clone;
  }
}

bool _notProtectedInline(html_dom.Element _) => false;
