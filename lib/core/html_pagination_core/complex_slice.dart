enum HtmlComplexBoundaryKind {
  blockEnd,
  hardBreak,
  sentenceEnd,
  wordEnd,
  graphemeEnd,
  rubyClusterEnd,
  protectedInlineEnd,
  atomEnd,
}

enum HtmlComplexProtectedRangeKind { ruby, inlineWidget }

final class HtmlComplexBoundary {
  const HtmlComplexBoundary({
    required this.textOffset,
    required this.sourceRuneOffset,
    required this.kind,
    required this.preference,
  });

  /// Local grapheme boundary, including synthetic textless widgets.
  final int textOffset;
  final int sourceRuneOffset;
  final HtmlComplexBoundaryKind kind;
  final int preference;
}

final class HtmlComplexProtectedRange {
  const HtmlComplexProtectedRange({
    required this.startOffset,
    required this.endOffset,
    required this.kind,
  });

  final int startOffset;
  final int endOffset;
  final HtmlComplexProtectedRangeKind kind;

  bool containsInteriorOffset(int offset) =>
      offset > startOffset && offset < endOffset;
}

final class HtmlComplexSlice {
  const HtmlComplexSlice({
    required this.html,
    required this.startOffset,
    required this.endOffset,
    required this.sourceRuneStart,
    required this.sourceRuneEnd,
    required this.hasRenderableContent,
    required this.domNodeCount,
  });

  final String html;

  /// Local grapheme range, independent of any persisted text coordinates.
  final int startOffset;
  final int endOffset;
  final int sourceRuneStart;
  final int sourceRuneEnd;
  final bool hasRenderableContent;

  /// Retained element, text and opaque nodes, excluding the fragment root.
  final int domNodeCount;

  /// Includes inline BR and excludes textless widgets.
  int get sourceRuneLength => sourceRuneEnd - sourceRuneStart;
}

abstract interface class HtmlComplexSliceSession {
  int get textLength;
  int get sourceRuneLength;

  /// Immutable legal boundaries, sorted by unique [HtmlComplexBoundary.textOffset].
  /// The final boundary is [textLength], including for an empty session.
  List<HtmlComplexBoundary> get boundaries;
  List<HtmlComplexProtectedRange> get protectedRanges;

  bool isLegalBoundary(int textOffset);

  /// Index of the first boundary strictly after [startOffset], or
  /// `boundaries.length` if none exists. The query may be inside a protected
  /// range, but must stay within `[0, textLength]`.
  int firstBoundaryIndexAfter(int startOffset);

  HtmlComplexSlice slice({required int startOffset, required int endOffset});
}
