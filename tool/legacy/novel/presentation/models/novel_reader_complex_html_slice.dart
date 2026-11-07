import 'package:flutter/foundation.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

typedef NovelReaderComplexBoundaryKind = HtmlComplexBoundaryKind;
typedef NovelReaderComplexProtectedRangeKind = HtmlComplexProtectedRangeKind;
typedef NovelReaderComplexHtmlProtectedRange = HtmlComplexProtectedRange;

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
final class NovelReaderComplexHtmlSlice {
  const NovelReaderComplexHtmlSlice({
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.startOffset,
    required this.endOffset,
    required this.hasRenderableContent,
    required this.domNodeCount,
    required this.sourceRuneLength,
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

  /// Source-rune span, including inline BR and excluding textless widgets.
  /// This is not the grapheme range or the projected semantic anchor distance.
  final int sourceRuneLength;
}

abstract interface class NovelReaderComplexHtmlSliceSession {
  /// Pure source-coordinate session; business anchors stay in this Host adapter.
  HtmlComplexSliceSession get coreSession;

  /// Projects an already cloned slice without slicing or parsing its HTML again.
  NovelReaderComplexHtmlSlice projectSlice(HtmlComplexSlice slice);

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
