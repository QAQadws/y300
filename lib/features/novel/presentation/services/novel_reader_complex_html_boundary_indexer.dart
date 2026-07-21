import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_dom_text_index.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_protected_inline_node_adapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';

abstract interface class NovelReaderComplexHtmlBoundaryIndexer {
  NovelReaderComplexHtmlSliceSession prepare({
    required String html,
    required NovelReaderTextAnchor startAnchor,
  });
}

final class DefaultNovelReaderComplexHtmlBoundaryIndexer
    implements NovelReaderComplexHtmlBoundaryIndexer {
  const DefaultNovelReaderComplexHtmlBoundaryIndexer({
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
    this.protectedInlineNodeAdapter =
        const DefaultNovelReaderProtectedInlineNodeAdapter(),
  }) : _fragmentCodec = fragmentCodec;

  final ForumHtmlFragmentCodec _fragmentCodec;
  final NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter;

  @override
  NovelReaderComplexHtmlSliceSession prepare({
    required String html,
    required NovelReaderTextAnchor startAnchor,
  }) {
    final index = NovelReaderHtmlDomTextIndex.parse(
      html,
      fragmentCodec: _fragmentCodec,
      protectedInlineNodeAdapter: protectedInlineNodeAdapter,
    );
    final collector = _ComplexBoundaryCollector(
      startAnchor: startAnchor,
      textLength: index.graphemeLength,
    );
    for (final node in index.roots) {
      collector.visit(node);
    }
    return _DefaultNovelReaderComplexHtmlSliceSession(
      index: index,
      startAnchor: startAnchor,
      boundaries: collector.finishBoundaries(),
      protectedRanges: collector.finishProtectedRanges(),
    );
  }
}

final class _DefaultNovelReaderComplexHtmlSliceSession
    implements NovelReaderComplexHtmlSliceSession {
  _DefaultNovelReaderComplexHtmlSliceSession({
    required NovelReaderHtmlDomTextIndex index,
    required this.startAnchor,
    required List<NovelReaderComplexHtmlBoundary> boundaries,
    required List<NovelReaderComplexHtmlProtectedRange> protectedRanges,
  }) : _index = index,
       boundaries = List<NovelReaderComplexHtmlBoundary>.unmodifiable(
         boundaries,
       ),
       protectedRanges =
           List<NovelReaderComplexHtmlProtectedRange>.unmodifiable(
             protectedRanges,
           ),
       _legalOffsets = <int>{
         0,
         ...boundaries.map((boundary) => boundary.textOffset),
       };

  final NovelReaderHtmlDomTextIndex _index;
  final NovelReaderTextAnchor startAnchor;

  @override
  int get textLength => _index.graphemeLength;

  @override
  final List<NovelReaderComplexHtmlBoundary> boundaries;

  @override
  final List<NovelReaderComplexHtmlProtectedRange> protectedRanges;

  final Set<int> _legalOffsets;

  @override
  bool isLegalBoundary(int textOffset) => _legalOffsets.contains(textOffset);

  @override
  NovelReaderComplexHtmlSlice slice({
    required int startOffset,
    required int endOffset,
  }) {
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
    return NovelReaderComplexHtmlSlice(
      html: sliced.html,
      startAnchor: _anchorAt(startOffset),
      endAnchor: _anchorAt(endOffset),
      startOffset: startOffset,
      endOffset: endOffset,
      hasRenderableContent: sliced.hasRenderableContent,
    );
  }

  NovelReaderTextAnchor _anchorAt(int offset) {
    return startAnchor.copyWith(
      textOffset:
          startAnchor.textOffset + _visibleTextOffset(offset, protectedRanges),
    );
  }
}

final class _ComplexBoundaryCollector {
  _ComplexBoundaryCollector({
    required this.startAnchor,
    required this.textLength,
  });

  final NovelReaderTextAnchor startAnchor;
  final int textLength;
  final Map<int, _BoundaryCandidate> _candidates = <int, _BoundaryCandidate>{};
  final List<NovelReaderComplexHtmlProtectedRange> _protectedRanges =
      <NovelReaderComplexHtmlProtectedRange>[];

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

  void visit(NovelReaderHtmlDomIndexedNode node) {
    if (node is NovelReaderHtmlDomIndexedTextNode) {
      _visitText(node);
      return;
    }
    if (node is! NovelReaderHtmlDomIndexedElementNode) {
      return;
    }
    final protectedKind = node.protectedKind;
    if (protectedKind != null) {
      final rangeKind =
          protectedKind == NovelReaderHtmlDomProtectedNodeKind.ruby
          ? NovelReaderComplexProtectedRangeKind.ruby
          : NovelReaderComplexProtectedRangeKind.inlineWidget;
      _protectedRanges.add(
        NovelReaderComplexHtmlProtectedRange(
          startOffset: node.graphemeStart,
          endOffset: node.graphemeEnd,
          kind: rangeKind,
        ),
      );
      _put(
        node.graphemeEnd,
        protectedKind == NovelReaderHtmlDomProtectedNodeKind.ruby
            ? NovelReaderComplexBoundaryKind.rubyClusterEnd
            : NovelReaderComplexBoundaryKind.protectedInlineEnd,
      );
      return;
    }
    if (node.tagName == 'br') {
      _put(node.graphemeStart, NovelReaderComplexBoundaryKind.hardBreak);
      return;
    }
    for (final child in node.children) {
      visit(child);
    }
    if (_blockTags.contains(node.tagName)) {
      _put(node.graphemeEnd, NovelReaderComplexBoundaryKind.blockEnd);
    }
  }

  void _visitText(NovelReaderHtmlDomIndexedTextNode node) {
    for (var index = 0; index < node.graphemes.length; index += 1) {
      final current = node.graphemes[index];
      final next = index + 1 < node.graphemes.length
          ? node.graphemes[index + 1]
          : null;
      final kind = _textBoundaryKind(current: current, next: next);
      _put(node.graphemeStart + index + 1, kind);
    }
  }

  NovelReaderComplexBoundaryKind _textBoundaryKind({
    required String current,
    required String? next,
  }) {
    if (_sentenceEndPattern.hasMatch(current)) {
      return NovelReaderComplexBoundaryKind.sentenceEnd;
    }
    if (_wordDelimiterPattern.hasMatch(current) ||
        (next != null && _wordDelimiterPattern.hasMatch(next))) {
      return NovelReaderComplexBoundaryKind.wordEnd;
    }
    return NovelReaderComplexBoundaryKind.graphemeEnd;
  }

  void _put(int offset, NovelReaderComplexBoundaryKind kind) {
    final candidate = _BoundaryCandidate(
      kind: kind,
      preference: _preference(kind),
    );
    final previous = _candidates[offset];
    if (previous == null || candidate.preference > previous.preference) {
      _candidates[offset] = candidate;
    }
  }

  List<NovelReaderComplexHtmlBoundary> finishBoundaries() {
    _put(textLength, NovelReaderComplexBoundaryKind.atomEnd);
    for (final range in _protectedRanges) {
      _candidates.removeWhere(
        (offset, _) => range.containsInteriorOffset(offset),
      );
    }
    final offsets = _candidates.keys.toList()..sort();
    return offsets
        .map((offset) {
          final candidate = _candidates[offset]!;
          return NovelReaderComplexHtmlBoundary(
            textOffset: offset,
            anchor: startAnchor.copyWith(
              textOffset:
                  startAnchor.textOffset +
                  _visibleTextOffset(offset, _protectedRanges),
            ),
            kind: candidate.kind,
            preference: candidate.preference,
          );
        })
        .toList(growable: false);
  }

  List<NovelReaderComplexHtmlProtectedRange> finishProtectedRanges() {
    _protectedRanges.sort(
      (left, right) => left.startOffset.compareTo(right.startOffset),
    );
    return List<NovelReaderComplexHtmlProtectedRange>.unmodifiable(
      _protectedRanges,
    );
  }

  int _preference(NovelReaderComplexBoundaryKind kind) {
    return switch (kind) {
      NovelReaderComplexBoundaryKind.atomEnd => 1000,
      NovelReaderComplexBoundaryKind.blockEnd => 900,
      NovelReaderComplexBoundaryKind.hardBreak => 800,
      NovelReaderComplexBoundaryKind.rubyClusterEnd ||
      NovelReaderComplexBoundaryKind.protectedInlineEnd => 750,
      NovelReaderComplexBoundaryKind.sentenceEnd => 700,
      NovelReaderComplexBoundaryKind.wordEnd => 600,
      NovelReaderComplexBoundaryKind.graphemeEnd => 500,
    };
  }

  static final _sentenceEndPattern = RegExp(r'^[。！？!?；;…]+$');
  static final _wordDelimiterPattern = RegExp(
    r'''^[\s\u00A0\u3000，、：:,.()（）「」『』“”"'-]+$''',
  );
}

int _visibleTextOffset(
  int indexedOffset,
  List<NovelReaderComplexHtmlProtectedRange> protectedRanges,
) {
  var syntheticPlaceholderCount = 0;
  for (final range in protectedRanges) {
    if (range.kind == NovelReaderComplexProtectedRangeKind.inlineWidget &&
        range.endOffset <= indexedOffset) {
      syntheticPlaceholderCount += range.endOffset - range.startOffset;
    }
  }
  return indexedOffset - syntheticPlaceholderCount;
}

final class _BoundaryCandidate {
  const _BoundaryCandidate({required this.kind, required this.preference});

  final NovelReaderComplexBoundaryKind kind;
  final int preference;
}
