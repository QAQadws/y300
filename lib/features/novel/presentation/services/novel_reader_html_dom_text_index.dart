import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';

enum NovelReaderHtmlDomProtectedNodeKind { ruby, inlineWidget }

final class NovelReaderHtmlDomTextSlice {
  const NovelReaderHtmlDomTextSlice({
    required this.html,
    required this.hasRenderableContent,
  });

  final String html;
  final bool hasRenderableContent;
}

/// Shared immutable DOM index used by safe rune slicing and complex grapheme
/// slicing. Parsing happens only in [parse]; all range operations clone the
/// indexed tree without reparsing HTML.
final class NovelReaderHtmlDomTextIndex {
  NovelReaderHtmlDomTextIndex._({
    required this.roots,
    required this.runeLength,
    required this.graphemeLength,
  });

  factory NovelReaderHtmlDomTextIndex.parse(
    String html, {
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
  }) {
    final fragment = fragmentCodec.parse(html);
    final cursor = _HtmlTextIndexCursor();
    final roots = fragment.nodes
        .map((node) => _indexNode(node, cursor))
        .toList(growable: false);
    return NovelReaderHtmlDomTextIndex._(
      roots: List<NovelReaderHtmlDomIndexedNode>.unmodifiable(roots),
      runeLength: cursor.runeOffset,
      graphemeLength: cursor.graphemeOffset,
    );
  }

  final List<NovelReaderHtmlDomIndexedNode> roots;
  final int runeLength;
  final int graphemeLength;

  NovelReaderHtmlDomTextSlice sliceRunes({
    required int start,
    required int end,
  }) {
    _validateRange(start: start, end: end, length: runeLength);
    final nodes = roots
        .map((node) => node.sliceRunes(start, end))
        .whereType<html_dom.Node>()
        .toList(growable: false);
    return _result(nodes);
  }

  NovelReaderHtmlDomTextSlice sliceGraphemes({
    required int start,
    required int end,
  }) {
    _validateRange(start: start, end: end, length: graphemeLength);
    final nodes = roots
        .map((node) => node.sliceGraphemes(start, end))
        .whereType<html_dom.Node>()
        .toList(growable: false);
    return _result(nodes);
  }

  NovelReaderHtmlDomTextSlice _result(List<html_dom.Node> nodes) {
    return NovelReaderHtmlDomTextSlice(
      html: nodes.map(_serializeNode).join(),
      hasRenderableContent: nodes.any(_hasRenderableContent),
    );
  }

  static NovelReaderHtmlDomIndexedNode _indexNode(
    html_dom.Node node,
    _HtmlTextIndexCursor cursor,
  ) {
    final runeStart = cursor.runeOffset;
    final graphemeStart = cursor.graphemeOffset;
    if (node is html_dom.Text) {
      final runes = node.data.runes.toList(growable: false);
      final graphemes = node.data.characters.toList(growable: false);
      cursor.runeOffset += runes.length;
      cursor.graphemeOffset += graphemes.length;
      return NovelReaderHtmlDomIndexedTextNode(
        original: node,
        runeStart: runeStart,
        runeEnd: cursor.runeOffset,
        graphemeStart: graphemeStart,
        graphemeEnd: cursor.graphemeOffset,
        runes: runes,
        graphemes: graphemes,
      );
    }
    if (node is html_dom.Element) {
      final protectedKind = _protectedKind(node);
      final children = node.nodes
          .map((child) => _indexNode(child, cursor))
          .toList(growable: false);
      if (protectedKind != null && cursor.graphemeOffset == graphemeStart) {
        cursor.graphemeOffset += 1;
      }
      return NovelReaderHtmlDomIndexedElementNode(
        original: node,
        runeStart: runeStart,
        runeEnd: cursor.runeOffset,
        graphemeStart: graphemeStart,
        graphemeEnd: cursor.graphemeOffset,
        children: List<NovelReaderHtmlDomIndexedNode>.unmodifiable(children),
        protectedKind: protectedKind,
      );
    }
    return NovelReaderHtmlDomIndexedOpaqueNode(
      original: node,
      runeStart: runeStart,
      runeEnd: runeStart,
      graphemeStart: graphemeStart,
      graphemeEnd: graphemeStart,
    );
  }

  static NovelReaderHtmlDomProtectedNodeKind? _protectedKind(
    html_dom.Element element,
  ) {
    final tag = element.localName?.toLowerCase();
    if (tag == 'ruby') {
      return NovelReaderHtmlDomProtectedNodeKind.ruby;
    }
    if (element.attributes.containsKey('data-y300-protected-inline')) {
      return NovelReaderHtmlDomProtectedNodeKind.inlineWidget;
    }
    if (tag != 'img') {
      return null;
    }
    final src = element.attributes['src']?.toLowerCase() ?? '';
    final classes = element.classes.map((value) => value.toLowerCase());
    if (src.contains('static/image/smiley/') ||
        src.contains('/smiley/') ||
        classes.any((value) => value.contains('smilie'))) {
      return NovelReaderHtmlDomProtectedNodeKind.inlineWidget;
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

  static bool _hasRenderableContent(html_dom.Node node) {
    if (node is html_dom.Text) {
      return _renderableTextPattern.hasMatch(node.data);
    }
    if (node is! html_dom.Element) {
      return false;
    }
    if (_protectedKind(node) != null ||
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
    return node.nodes.any(_hasRenderableContent);
  }

  static String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.text ?? '';
  }

  static final _renderableTextPattern = RegExp(
    r'[^\s\u00A0\u200B\u2060\u3000\uFEFF]',
  );
}

sealed class NovelReaderHtmlDomIndexedNode {
  const NovelReaderHtmlDomIndexedNode({
    required this.original,
    required this.runeStart,
    required this.runeEnd,
    required this.graphemeStart,
    required this.graphemeEnd,
  });

  final html_dom.Node original;
  final int runeStart;
  final int runeEnd;
  final int graphemeStart;
  final int graphemeEnd;

  html_dom.Node? sliceRunes(int rangeStart, int rangeEnd);

  html_dom.Node? sliceGraphemes(int rangeStart, int rangeEnd);

  bool ownsRuneRange(int rangeStart, int rangeEnd) => _ownsRange(
    start: runeStart,
    end: runeEnd,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );

  bool ownsGraphemeRange(int rangeStart, int rangeEnd) => _ownsRange(
    start: graphemeStart,
    end: graphemeEnd,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );

  bool _ownsRange({
    required int start,
    required int end,
    required int rangeStart,
    required int rangeEnd,
  }) {
    return start == end
        ? start >= rangeStart && start < rangeEnd
        : end > rangeStart && start < rangeEnd;
  }
}

final class NovelReaderHtmlDomIndexedTextNode
    extends NovelReaderHtmlDomIndexedNode {
  const NovelReaderHtmlDomIndexedTextNode({
    required super.original,
    required super.runeStart,
    required super.runeEnd,
    required super.graphemeStart,
    required super.graphemeEnd,
    required this.runes,
    required this.graphemes,
  });

  final List<int> runes;
  final List<String> graphemes;

  @override
  html_dom.Node? sliceRunes(int rangeStart, int rangeEnd) {
    final from = (rangeStart - runeStart).clamp(0, runes.length).toInt();
    final to = (rangeEnd - runeStart).clamp(0, runes.length).toInt();
    if (from >= to) {
      return null;
    }
    return html_dom.Text(String.fromCharCodes(runes.sublist(from, to)));
  }

  @override
  html_dom.Node? sliceGraphemes(int rangeStart, int rangeEnd) {
    final from = (rangeStart - graphemeStart)
        .clamp(0, graphemes.length)
        .toInt();
    final to = (rangeEnd - graphemeStart).clamp(0, graphemes.length).toInt();
    if (from >= to) {
      return null;
    }
    return html_dom.Text(graphemes.sublist(from, to).join());
  }
}

final class NovelReaderHtmlDomIndexedElementNode
    extends NovelReaderHtmlDomIndexedNode {
  const NovelReaderHtmlDomIndexedElementNode({
    required html_dom.Element super.original,
    required super.runeStart,
    required super.runeEnd,
    required super.graphemeStart,
    required super.graphemeEnd,
    required this.children,
    required this.protectedKind,
  });

  final List<NovelReaderHtmlDomIndexedNode> children;
  final NovelReaderHtmlDomProtectedNodeKind? protectedKind;

  String get tagName =>
      (original as html_dom.Element).localName?.toLowerCase() ?? '';

  @override
  html_dom.Node? sliceRunes(int rangeStart, int rangeEnd) {
    if (!ownsRuneRange(rangeStart, rangeEnd)) {
      return null;
    }
    if (runeStart == runeEnd) {
      return original.clone(true);
    }
    return _sliceChildren((child) => child.sliceRunes(rangeStart, rangeEnd));
  }

  @override
  html_dom.Node? sliceGraphemes(int rangeStart, int rangeEnd) {
    if (!ownsGraphemeRange(rangeStart, rangeEnd)) {
      return null;
    }
    if (protectedKind != null) {
      return rangeStart <= graphemeStart && rangeEnd >= graphemeEnd
          ? original.clone(true)
          : null;
    }
    if (graphemeStart == graphemeEnd) {
      return original.clone(true);
    }
    return _sliceChildren(
      (child) => child.sliceGraphemes(rangeStart, rangeEnd),
    );
  }

  html_dom.Node? _sliceChildren(
    html_dom.Node? Function(NovelReaderHtmlDomIndexedNode child) slice,
  ) {
    final clone = original.clone(false) as html_dom.Element;
    for (final child in children) {
      final sliced = slice(child);
      if (sliced != null) {
        clone.append(sliced);
      }
    }
    return clone.nodes.isEmpty ? null : clone;
  }
}

final class NovelReaderHtmlDomIndexedOpaqueNode
    extends NovelReaderHtmlDomIndexedNode {
  const NovelReaderHtmlDomIndexedOpaqueNode({
    required super.original,
    required super.runeStart,
    required super.runeEnd,
    required super.graphemeStart,
    required super.graphemeEnd,
  });

  @override
  html_dom.Node? sliceRunes(int rangeStart, int rangeEnd) =>
      ownsRuneRange(rangeStart, rangeEnd) ? original.clone(true) : null;

  @override
  html_dom.Node? sliceGraphemes(int rangeStart, int rangeEnd) =>
      ownsGraphemeRange(rangeStart, rangeEnd) ? original.clone(true) : null;
}

final class _HtmlTextIndexCursor {
  int runeOffset = 0;
  int graphemeOffset = 0;
}
