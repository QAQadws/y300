import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/novel/presentation/services/novel_reader_protected_inline_node_adapter.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

enum NovelReaderHtmlDomProtectedNodeKind { ruby, inlineWidget }

final class NovelReaderHtmlDomTextSlice {
  const NovelReaderHtmlDomTextSlice({
    required this.html,
    required this.hasRenderableContent,
    required this.domNodeCount,
  });

  final String html;
  final bool hasRenderableContent;

  /// Retained element, text and opaque nodes, excluding the fragment root.
  final int domNodeCount;
}

final class NovelReaderHtmlDomGrapheme {
  const NovelReaderHtmlDomGrapheme({
    required this.text,
    required this.sourceStart,
    required this.sourceEnd,
    required this.isText,
  });

  final String text;
  final int sourceStart;
  final int sourceEnd;
  final bool isText;
}

/// Immutable DOM index shared by source-rune and grapheme slicing.
/// Inline BR occupies one source rune; textless widgets occupy only a synthetic
/// grapheme. Adjacent inline text is segmented together, including across spans.
final class NovelReaderHtmlDomTextIndex {
  NovelReaderHtmlDomTextIndex._({
    required this.roots,
    required this.runeLength,
    required this.graphemes,
    required List<int> sourceRuneBoundaries,
    required NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter,
  }) : _sourceRuneBoundaries = sourceRuneBoundaries,
       _protectedInlineNodeAdapter = protectedInlineNodeAdapter;

  factory NovelReaderHtmlDomTextIndex.parse(
    String html, {
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
    NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter =
        const DefaultNovelReaderProtectedInlineNodeAdapter(),
  }) {
    final fragment = fragmentCodec.parse(html);
    final builder = _HtmlTextIndexBuilder(protectedInlineNodeAdapter);
    final drafts = fragment.nodes.map(builder.visit).toList(growable: false);
    builder.flushText();
    final boundaries = List<int>.unmodifiable(<int>[
      0,
      ...builder.graphemes.map((grapheme) => grapheme.sourceEnd),
    ]);
    return NovelReaderHtmlDomTextIndex._(
      roots: List<NovelReaderHtmlDomIndexedNode>.unmodifiable(
        drafts.map((draft) => draft.freeze(boundaries)),
      ),
      runeLength: builder.runeOffset,
      graphemes: List<NovelReaderHtmlDomGrapheme>.unmodifiable(
        builder.graphemes,
      ),
      sourceRuneBoundaries: boundaries,
      protectedInlineNodeAdapter: protectedInlineNodeAdapter,
    );
  }

  final List<NovelReaderHtmlDomIndexedNode> roots;
  final int runeLength;
  final List<NovelReaderHtmlDomGrapheme> graphemes;
  final List<int> _sourceRuneBoundaries;
  final NovelReaderProtectedInlineNodeAdapter _protectedInlineNodeAdapter;

  int get graphemeLength => graphemes.length;

  int sourceRuneAtGraphemeBoundary(int offset) {
    RangeError.checkValueInInterval(offset, 0, graphemeLength, 'offset');
    return _sourceRuneBoundaries[offset];
  }

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
      hasRenderableContent: nodes.any(
        (node) => _hasRenderableContent(node, _protectedInlineNodeAdapter),
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

  static NovelReaderHtmlDomProtectedNodeKind? _protectedKind(
    html_dom.Element element,
    NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter,
  ) {
    if (element.localName?.toLowerCase() == 'ruby') {
      return NovelReaderHtmlDomProtectedNodeKind.ruby;
    }
    if (protectedInlineNodeAdapter.assess(element).isStable) {
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

  static bool _hasRenderableContent(
    html_dom.Node node,
    NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter,
  ) {
    if (node is html_dom.Text) {
      return _renderableTextPattern.hasMatch(node.data);
    }
    if (node is! html_dom.Element) {
      return false;
    }
    if (_protectedKind(node, protectedInlineNodeAdapter) != null ||
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
      (child) => _hasRenderableContent(child, protectedInlineNodeAdapter),
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
  }) => start == end
      ? start >= rangeStart && start < rangeEnd
      : end > rangeStart && start < rangeEnd;
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
    required List<int> sourceRuneBoundaries,
  }) : _sourceRuneBoundaries = sourceRuneBoundaries;

  final List<int> runes;
  final List<int> _sourceRuneBoundaries;

  @override
  html_dom.Node? sliceRunes(int rangeStart, int rangeEnd) {
    final from = (rangeStart - runeStart).clamp(0, runes.length).toInt();
    final to = (rangeEnd - runeStart).clamp(0, runes.length).toInt();
    if (from >= to) return null;
    return html_dom.Text(String.fromCharCodes(runes.sublist(from, to)));
  }

  @override
  html_dom.Node? sliceGraphemes(int rangeStart, int rangeEnd) {
    // A grapheme may span several text nodes. Every contributing node uses the
    // same global source boundaries rather than segmenting its own text.
    return sliceRunes(
      _sourceRuneBoundaries[rangeStart],
      _sourceRuneBoundaries[rangeEnd],
    );
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
    if (!ownsRuneRange(rangeStart, rangeEnd)) return null;
    if (tagName == 'br' || runeStart == runeEnd) {
      return original.clone(true);
    }
    return _sliceChildren((child) => child.sliceRunes(rangeStart, rangeEnd));
  }

  @override
  html_dom.Node? sliceGraphemes(int rangeStart, int rangeEnd) {
    if (!ownsGraphemeRange(rangeStart, rangeEnd)) return null;
    if (protectedKind != null || tagName == 'br') {
      return rangeStart <= graphemeStart && rangeEnd >= graphemeEnd
          ? original.clone(true)
          : null;
    }
    if (graphemeStart == graphemeEnd) return original.clone(true);
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
      if (sliced != null) clone.append(sliced);
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

final class _HtmlTextIndexBuilder {
  _HtmlTextIndexBuilder(this.protectedInlineNodeAdapter);

  final NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter;
  final List<NovelReaderHtmlDomGrapheme> graphemes = [];
  final StringBuffer _text = StringBuffer();
  int _textStart = 0;
  int runeOffset = 0;

  _HtmlIndexedNodeDraft visit(html_dom.Node node) {
    final runeStart = runeOffset;
    if (node is html_dom.Text) {
      if (_text.isEmpty) _textStart = runeStart;
      _text.write(node.data);
      runeOffset += node.data.runes.length;
      return _HtmlIndexedNodeDraft(
        original: node,
        runeStart: runeStart,
        runeEnd: runeOffset,
      );
    }
    if (node is! html_dom.Element ||
        node.localName == 'script' ||
        node.localName == 'style') {
      return _HtmlIndexedNodeDraft(
        original: node,
        runeStart: runeStart,
        runeEnd: runeStart,
      );
    }
    final tag = node.localName?.toLowerCase() ?? '';
    final protectedKind = NovelReaderHtmlDomTextIndex._protectedKind(
      node,
      protectedInlineNodeAdapter,
    );
    final separatesText =
        protectedKind != null || tag == 'br' || _blockTags.contains(tag);
    if (separatesText) flushText();
    final graphemeStart = graphemes.length;
    final children = <_HtmlIndexedNodeDraft>[];
    if (tag == 'br') {
      runeOffset += 1;
      graphemes.add(
        NovelReaderHtmlDomGrapheme(
          text: '\n',
          sourceStart: runeStart,
          sourceEnd: runeOffset,
          isText: false,
        ),
      );
    } else {
      children.addAll(node.nodes.map(visit));
      if (separatesText) flushText();
      if (protectedKind != null && graphemes.length == graphemeStart) {
        graphemes.add(
          NovelReaderHtmlDomGrapheme(
            text: '\uFFFC',
            sourceStart: runeOffset,
            sourceEnd: runeOffset,
            isText: false,
          ),
        );
      }
    }
    return _HtmlIndexedNodeDraft(
      original: node,
      runeStart: runeStart,
      runeEnd: runeOffset,
      children: children,
      protectedKind: protectedKind,
      explicitGraphemeStart: separatesText ? graphemeStart : null,
      explicitGraphemeEnd: separatesText ? graphemes.length : null,
    );
  }

  void flushText() {
    var sourceOffset = _textStart;
    for (final text in _text.toString().characters) {
      final end = sourceOffset + text.runes.length;
      graphemes.add(
        NovelReaderHtmlDomGrapheme(
          text: text,
          sourceStart: sourceOffset,
          sourceEnd: end,
          isText: true,
        ),
      );
      sourceOffset = end;
    }
    _text.clear();
  }

  static const _blockTags = <String>{
    'address',
    'article',
    'aside',
    'blockquote',
    'dd',
    'div',
    'dl',
    'dt',
    'figcaption',
    'figure',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'li',
    'main',
    'p',
    'pre',
    'section',
  };
}

final class _HtmlIndexedNodeDraft {
  _HtmlIndexedNodeDraft({
    required this.original,
    required this.runeStart,
    required this.runeEnd,
    this.children = const [],
    this.protectedKind,
    this.explicitGraphemeStart,
    this.explicitGraphemeEnd,
  });

  final html_dom.Node original;
  final int runeStart;
  final int runeEnd;
  final List<_HtmlIndexedNodeDraft> children;
  final NovelReaderHtmlDomProtectedNodeKind? protectedKind;
  final int? explicitGraphemeStart;
  final int? explicitGraphemeEnd;

  NovelReaderHtmlDomIndexedNode freeze(List<int> boundaries) {
    final node = original;
    final start = _upperBound(boundaries, runeStart) - 1;
    final end = runeStart == runeEnd ? start : _lowerBound(boundaries, runeEnd);
    if (node is html_dom.Text) {
      return NovelReaderHtmlDomIndexedTextNode(
        original: node,
        runeStart: runeStart,
        runeEnd: runeEnd,
        graphemeStart: start,
        graphemeEnd: end,
        runes: List<int>.unmodifiable(node.data.runes),
        sourceRuneBoundaries: boundaries,
      );
    }
    if (node is html_dom.Element &&
        node.localName != 'script' &&
        node.localName != 'style') {
      final indexedChildren = List<NovelReaderHtmlDomIndexedNode>.unmodifiable(
        children.map((child) => child.freeze(boundaries)),
      );
      // Zero-source siblings can share a rune boundary while occupying
      // different graphemes. An empty child must not hide a later widget.
      var childStart = start;
      var childEnd = end;
      if (indexedChildren.isNotEmpty) {
        childStart = indexedChildren.first.graphemeStart;
        childEnd = indexedChildren.first.graphemeEnd;
        for (final child in indexedChildren.skip(1)) {
          if (child.graphemeStart < childStart) {
            childStart = child.graphemeStart;
          }
          if (child.graphemeEnd > childEnd) childEnd = child.graphemeEnd;
        }
      }
      return NovelReaderHtmlDomIndexedElementNode(
        original: node,
        runeStart: runeStart,
        runeEnd: runeEnd,
        graphemeStart: explicitGraphemeStart ?? childStart,
        graphemeEnd: explicitGraphemeEnd ?? childEnd,
        children: indexedChildren,
        protectedKind: protectedKind,
      );
    }
    return NovelReaderHtmlDomIndexedOpaqueNode(
      original: node,
      runeStart: runeStart,
      runeEnd: runeEnd,
      graphemeStart: start,
      graphemeEnd: start,
    );
  }

  static int _lowerBound(List<int> values, int target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (values[middle] < target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static int _upperBound(List<int> values, int target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (values[middle] <= target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
