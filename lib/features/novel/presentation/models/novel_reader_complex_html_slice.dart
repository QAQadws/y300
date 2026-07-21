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
  });

  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final int startOffset;
  final int endOffset;
  final bool hasRenderableContent;
}

abstract interface class NovelReaderComplexHtmlSliceSession {
  int get textLength;

  List<NovelReaderComplexHtmlBoundary> get boundaries;

  List<NovelReaderComplexHtmlProtectedRange> get protectedRanges;

  bool isLegalBoundary(int textOffset);

  NovelReaderComplexHtmlSlice slice({
    required int startOffset,
    required int endOffset,
  });
}
