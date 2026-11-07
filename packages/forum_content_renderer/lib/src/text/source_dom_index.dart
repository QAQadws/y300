import 'package:characters/characters.dart';
import 'package:html/dom.dart' as html_dom;
import 'ports.dart';

enum HtmlDomProtectedNodeKind { ruby, inlineWidget }

final class HtmlDomGrapheme {
  const HtmlDomGrapheme({
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

/// Read-only source DOM index shared by rendering projections and legacy slicing.
/// Inline BR occupies one source rune; textless widgets occupy only a synthetic
/// grapheme. Adjacent inline text is segmented together, including across spans.
/// Parsed nodes are borrowed read-only; consumers must not mutate them.
/// This index neither slices nor serializes HTML.
final class HtmlSourceDomIndex {
  HtmlSourceDomIndex._({
    required this.roots,
    required this.runeLength,
    required this.graphemes,
    required List<int> sourceRuneBoundaries,
  }) : _sourceRuneBoundaries = sourceRuneBoundaries;

  factory HtmlSourceDomIndex.parse(
    String html, {
    HtmlFragmentParser fragmentParser = const DefaultHtmlFragmentParser(),
    HtmlProtectedInlinePredicate protectedInlinePredicate = _notProtectedInline,
  }) {
    final fragment = fragmentParser.parse(html);
    final builder = _HtmlTextIndexBuilder(protectedInlinePredicate);
    final drafts = fragment.nodes.map(builder.visit).toList(growable: false);
    builder.flushText();
    final boundaries = List<int>.unmodifiable(<int>[
      0,
      ...builder.graphemes.map((grapheme) => grapheme.sourceEnd),
    ]);
    return HtmlSourceDomIndex._(
      roots: List<HtmlDomIndexedNode>.unmodifiable(
        drafts.map((draft) => draft.freeze(boundaries)),
      ),
      runeLength: builder.runeOffset,
      graphemes: List<HtmlDomGrapheme>.unmodifiable(builder.graphemes),
      sourceRuneBoundaries: boundaries,
    );
  }

  final List<HtmlDomIndexedNode> roots;
  final int runeLength;
  final List<HtmlDomGrapheme> graphemes;
  final List<int> _sourceRuneBoundaries;

  int get graphemeLength => graphemes.length;

  int sourceRuneAtGraphemeBoundary(int offset) {
    RangeError.checkValueInInterval(offset, 0, graphemeLength, 'offset');
    return _sourceRuneBoundaries[offset];
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
}

sealed class HtmlDomIndexedNode {
  const HtmlDomIndexedNode({
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

final class HtmlDomIndexedTextNode extends HtmlDomIndexedNode {
  const HtmlDomIndexedTextNode({
    required super.original,
    required super.runeStart,
    required super.runeEnd,
    required super.graphemeStart,
    required super.graphemeEnd,
    required this.runes,
  });
  final List<int> runes;
}

final class HtmlDomIndexedElementNode extends HtmlDomIndexedNode {
  const HtmlDomIndexedElementNode({
    required html_dom.Element super.original,
    required super.runeStart,
    required super.runeEnd,
    required super.graphemeStart,
    required super.graphemeEnd,
    required this.children,
    required this.protectedKind,
  });
  final List<HtmlDomIndexedNode> children;
  final HtmlDomProtectedNodeKind? protectedKind;
  String get tagName =>
      (original as html_dom.Element).localName?.toLowerCase() ?? '';
}

final class HtmlDomIndexedOpaqueNode extends HtmlDomIndexedNode {
  const HtmlDomIndexedOpaqueNode({
    required super.original,
    required super.runeStart,
    required super.runeEnd,
    required super.graphemeStart,
    required super.graphemeEnd,
  });
}

final class _HtmlTextIndexBuilder {
  _HtmlTextIndexBuilder(this.protectedInlinePredicate);

  final HtmlProtectedInlinePredicate protectedInlinePredicate;
  final List<HtmlDomGrapheme> graphemes = [];
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
    final protectedKind = HtmlSourceDomIndex._protectedKind(
      node,
      protectedInlinePredicate,
    );
    final separatesText =
        protectedKind != null || tag == 'br' || _blockTags.contains(tag);
    if (separatesText) flushText();
    final graphemeStart = graphemes.length;
    final children = <_HtmlIndexedNodeDraft>[];
    if (tag == 'br') {
      runeOffset += 1;
      graphemes.add(
        HtmlDomGrapheme(
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
          HtmlDomGrapheme(
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
        HtmlDomGrapheme(
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
  final HtmlDomProtectedNodeKind? protectedKind;
  final int? explicitGraphemeStart;
  final int? explicitGraphemeEnd;

  HtmlDomIndexedNode freeze(List<int> boundaries) {
    final node = original;
    final start = _upperBound(boundaries, runeStart) - 1;
    final end = runeStart == runeEnd ? start : _lowerBound(boundaries, runeEnd);
    if (node is html_dom.Text) {
      return HtmlDomIndexedTextNode(
        original: node,
        runeStart: runeStart,
        runeEnd: runeEnd,
        graphemeStart: start,
        graphemeEnd: end,
        runes: List<int>.unmodifiable(node.data.runes),
      );
    }
    if (node is html_dom.Element &&
        node.localName != 'script' &&
        node.localName != 'style') {
      final indexedChildren = List<HtmlDomIndexedNode>.unmodifiable(
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
      return HtmlDomIndexedElementNode(
        original: node,
        runeStart: runeStart,
        runeEnd: runeEnd,
        graphemeStart: explicitGraphemeStart ?? childStart,
        graphemeEnd: explicitGraphemeEnd ?? childEnd,
        children: indexedChildren,
        protectedKind: protectedKind,
      );
    }
    return HtmlDomIndexedOpaqueNode(
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

bool _notProtectedInline(html_dom.Element element) => false;
