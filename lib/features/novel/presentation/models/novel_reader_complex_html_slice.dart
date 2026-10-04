import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

enum NovelReaderComplexBoundaryKind {
  blockEnd,
  hardBreak,
  sentenceEnd,
  wordEnd,
  graphemeEnd,
  rubyClusterEnd,
  protectedInlineEnd,
  atomEnd,
}

enum NovelReaderComplexProtectedRangeKind { ruby, inlineWidget }

@immutable
final class NovelReaderComplexHtmlBoundary {
  const NovelReaderComplexHtmlBoundary({
    required this.textOffset,
    required this.anchor,
    required this.kind,
    required this.preference,
  });

  final int textOffset;
  final NovelReaderTextAnchor anchor;
  final NovelReaderComplexBoundaryKind kind;
  final int preference;
}

@immutable
final class NovelReaderComplexHtmlProtectedRange {
  const NovelReaderComplexHtmlProtectedRange({
    required this.startOffset,
    required this.endOffset,
    required this.kind,
  });

  final int startOffset;
  final int endOffset;
  final NovelReaderComplexProtectedRangeKind kind;

  bool containsInteriorOffset(int offset) =>
      offset > startOffset && offset < endOffset;
}

@immutable
final class NovelReaderComplexHtmlSlice {
  const NovelReaderComplexHtmlSlice({
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.startOffset,
    required this.endOffset,
    required this.hasRenderableContent,
    required this.domNodeCount,
  });

  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final int startOffset;
  final int endOffset;
  final bool hasRenderableContent;

  /// Element, text and opaque nodes retained in the slice DOM, excluding the
  /// fragment root. This describes the slice, not any buffered page HTML.
  final int domNodeCount;
}

abstract interface class NovelReaderComplexHtmlSliceSession {
  int get textLength;

  /// Immutable legal boundaries, sorted by unique
  /// [NovelReaderComplexHtmlBoundary.textOffset] values. The final boundary is
  /// [textLength], including for an empty session.
  List<NovelReaderComplexHtmlBoundary> get boundaries;

  List<NovelReaderComplexHtmlProtectedRange> get protectedRanges;

  bool isLegalBoundary(int textOffset);

  /// Index of the first boundary strictly after [startOffset], or
  /// `boundaries.length` if none exists. Queries may be inside protected ranges,
  /// but must stay within `[0, textLength]`.
  int firstBoundaryIndexAfter(int startOffset);

  NovelReaderComplexHtmlSlice slice({
    required int startOffset,
    required int endOffset,
  });
}
