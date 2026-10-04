import 'package:html/dom.dart' as html_dom;

import 'complex_slice.dart';
import 'dom_text_index.dart';
import 'ports.dart';

abstract interface class HtmlComplexBoundaryIndexer {
  HtmlComplexSliceSession prepare({required String html});
}

final class DefaultHtmlComplexBoundaryIndexer
    implements HtmlComplexBoundaryIndexer {
  const DefaultHtmlComplexBoundaryIndexer({
    HtmlFragmentParser fragmentParser = const DefaultHtmlFragmentParser(),
    this.protectedInlinePredicate = _notProtectedInline,
  }) : _fragmentParser = fragmentParser;

  final HtmlFragmentParser _fragmentParser;
  final HtmlProtectedInlinePredicate protectedInlinePredicate;

  @override
  HtmlComplexSliceSession prepare({required String html}) {
    final index = HtmlDomTextIndex.parse(
      html,
      fragmentParser: _fragmentParser,
      protectedInlinePredicate: protectedInlinePredicate,
    );
    final collector = _ComplexBoundaryCollector(index: index);
    collector.collectTextBoundaries();
    for (final node in index.roots) {
      collector.visit(node);
    }
    return _DefaultHtmlComplexSliceSession(
      index: index,
      boundaries: collector.finishBoundaries(),
      protectedRanges: collector.finishProtectedRanges(),
    );
  }
}

final class _DefaultHtmlComplexSliceSession implements HtmlComplexSliceSession {
  _DefaultHtmlComplexSliceSession({
    required HtmlDomTextIndex index,
    required List<HtmlComplexBoundary> boundaries,
    required List<HtmlComplexProtectedRange> protectedRanges,
  }) : _index = index,
       boundaries = List<HtmlComplexBoundary>.unmodifiable(boundaries),
       protectedRanges = List<HtmlComplexProtectedRange>.unmodifiable(
         protectedRanges,
       ),
       _legalOffsets = <int>{
         0,
         ...boundaries.map((boundary) => boundary.textOffset),
       };

  final HtmlDomTextIndex _index;

  @override
  int get textLength => _index.graphemeLength;

  @override
  int get sourceRuneLength => _index.runeLength;

  @override
  final List<HtmlComplexBoundary> boundaries;

  @override
  final List<HtmlComplexProtectedRange> protectedRanges;

  final Set<int> _legalOffsets;

  @override
  bool isLegalBoundary(int textOffset) => _legalOffsets.contains(textOffset);

  @override
  int firstBoundaryIndexAfter(int startOffset) {
    RangeError.checkValueInInterval(startOffset, 0, textLength, 'startOffset');
    var low = 0;
    var high = boundaries.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (boundaries[middle].textOffset <= startOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  @override
  HtmlComplexSlice slice({required int startOffset, required int endOffset}) {
    if (startOffset < 0 || endOffset < startOffset || endOffset > textLength) {
      throw RangeError(
        'Invalid complex HTML range [$startOffset, $endOffset) for '
        '$textLength.',
      );
    }
    if (!isLegalBoundary(startOffset) || !isLegalBoundary(endOffset)) {
      throw ArgumentError(
        'Complex HTML slices must start and end at legal boundaries: '
        '[$startOffset, $endOffset).',
      );
    }
    final sliced = _index.sliceGraphemes(start: startOffset, end: endOffset);
    return HtmlComplexSlice(
      html: sliced.html,
      sourceRuneStart: _index.sourceRuneAtGraphemeBoundary(startOffset),
      sourceRuneEnd: _index.sourceRuneAtGraphemeBoundary(endOffset),
      startOffset: startOffset,
      endOffset: endOffset,
      hasRenderableContent: sliced.hasRenderableContent,
      domNodeCount: sliced.domNodeCount,
    );
  }
}

final class _ComplexBoundaryCollector {
  _ComplexBoundaryCollector({required this.index});

  final HtmlDomTextIndex index;
  int get textLength => index.graphemeLength;
  final Map<int, _BoundaryCandidate> _candidates = <int, _BoundaryCandidate>{};
  final List<HtmlComplexProtectedRange> _protectedRanges =
      <HtmlComplexProtectedRange>[];

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

  void visit(HtmlDomIndexedNode node) {
    if (node is HtmlDomIndexedTextNode) {
      return;
    }
    if (node is! HtmlDomIndexedElementNode) {
      return;
    }
    final protectedKind = node.protectedKind;
    if (protectedKind != null) {
      final rangeKind = protectedKind == HtmlDomProtectedNodeKind.ruby
          ? HtmlComplexProtectedRangeKind.ruby
          : HtmlComplexProtectedRangeKind.inlineWidget;
      _protectedRanges.add(
        HtmlComplexProtectedRange(
          startOffset: node.graphemeStart,
          endOffset: node.graphemeEnd,
          kind: rangeKind,
        ),
      );
      _put(
        node.graphemeEnd,
        protectedKind == HtmlDomProtectedNodeKind.ruby
            ? HtmlComplexBoundaryKind.rubyClusterEnd
            : HtmlComplexBoundaryKind.protectedInlineEnd,
      );
      return;
    }
    if (node.tagName == 'br') {
      _put(node.graphemeStart, HtmlComplexBoundaryKind.hardBreak);
      return;
    }
    for (final child in node.children) {
      visit(child);
    }
    if (_blockTags.contains(node.tagName)) {
      _put(node.graphemeEnd, HtmlComplexBoundaryKind.blockEnd);
    }
  }

  void collectTextBoundaries() {
    final graphemes = index.graphemes;
    for (var offset = 0; offset < graphemes.length; offset += 1) {
      final current = graphemes[offset];
      if (!current.isText) continue;
      final next = offset + 1 < graphemes.length && graphemes[offset + 1].isText
          ? graphemes[offset + 1].text
          : null;
      final kind = _textBoundaryKind(current: current.text, next: next);
      _put(offset + 1, kind);
    }
  }

  HtmlComplexBoundaryKind _textBoundaryKind({
    required String current,
    required String? next,
  }) {
    if (_sentenceEndPattern.hasMatch(current)) {
      return HtmlComplexBoundaryKind.sentenceEnd;
    }
    if (_wordDelimiterPattern.hasMatch(current) ||
        (next != null && _wordDelimiterPattern.hasMatch(next))) {
      return HtmlComplexBoundaryKind.wordEnd;
    }
    return HtmlComplexBoundaryKind.graphemeEnd;
  }

  void _put(int offset, HtmlComplexBoundaryKind kind) {
    final candidate = _BoundaryCandidate(
      kind: kind,
      preference: _preference(kind),
    );
    final previous = _candidates[offset];
    if (previous == null || candidate.preference > previous.preference) {
      _candidates[offset] = candidate;
    }
  }

  List<HtmlComplexBoundary> finishBoundaries() {
    _put(textLength, HtmlComplexBoundaryKind.atomEnd);
    for (final range in _protectedRanges) {
      _candidates.removeWhere(
        (offset, _) => range.containsInteriorOffset(offset),
      );
    }
    final offsets = _candidates.keys.toList()..sort();
    return offsets
        .map((offset) {
          final candidate = _candidates[offset]!;
          return HtmlComplexBoundary(
            textOffset: offset,
            sourceRuneOffset: index.sourceRuneAtGraphemeBoundary(offset),
            kind: candidate.kind,
            preference: candidate.preference,
          );
        })
        .toList(growable: false);
  }

  List<HtmlComplexProtectedRange> finishProtectedRanges() {
    _protectedRanges.sort(
      (left, right) => left.startOffset.compareTo(right.startOffset),
    );
    return List<HtmlComplexProtectedRange>.unmodifiable(_protectedRanges);
  }

  int _preference(HtmlComplexBoundaryKind kind) {
    return switch (kind) {
      HtmlComplexBoundaryKind.atomEnd => 1000,
      HtmlComplexBoundaryKind.blockEnd => 900,
      HtmlComplexBoundaryKind.hardBreak => 800,
      HtmlComplexBoundaryKind.rubyClusterEnd ||
      HtmlComplexBoundaryKind.protectedInlineEnd => 750,
      HtmlComplexBoundaryKind.sentenceEnd => 700,
      HtmlComplexBoundaryKind.wordEnd => 600,
      HtmlComplexBoundaryKind.graphemeEnd => 500,
    };
  }

  static final _sentenceEndPattern = RegExp(r'^[。！？!?；;…]+$');
  static final _wordDelimiterPattern = RegExp(
    r'''^[\s\u00A0\u3000，、：:,.()（）「」『』“”"'-]+$''',
  );
}

final class _BoundaryCandidate {
  const _BoundaryCandidate({required this.kind, required this.preference});

  final HtmlComplexBoundaryKind kind;
  final int preference;
}

bool _notProtectedInline(html_dom.Element element) => false;
