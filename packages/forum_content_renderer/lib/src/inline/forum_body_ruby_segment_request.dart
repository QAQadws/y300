import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';

typedef ForumBodyRubySpanRequest = ({
  ForumBodyTextRequest request,
  int startColumn,
  int endColumn,
  int annotationIndex,
  double gap,
});

typedef ForumBodyRubyGapRequest = ({
  int beforeColumn,
  ForumBodyTextRequest request,
});

typedef ForumBodyRubyAnnotationGapRequest = ({
  int beforeSpanIndex,
  ForumBodyTextRequest request,
  double gap,
});

/// Immutable original base/annotation requests for one unbroken component.
/// Native slots count empty base font struts, but never empty annotation glyphs.
/// Parent/source-window and complete-band retention remain page admission work.
final class ForumBodyRubySegmentRequest {
  ForumBodyRubySegmentRequest({
    required List<ForumBodyTextRequest> bases,
    required List<ForumBodyRubySide> sides,
    required List<ForumBodyRubySpanRequest> spans,
    List<ForumBodyRubyGapRequest> gaps = const [],
    List<ForumBodyRubyAnnotationGapRequest> annotationGaps = const [],
    this.direction = TextDirection.ltr,
    this.maxWidth = 16384,
  }) : bases = List.unmodifiable(bases),
       sides = List.unmodifiable(sides),
       spans = List.unmodifiable(spans),
       gaps = List.unmodifiable(gaps),
       annotationGaps = List.unmodifiable(annotationGaps),
       nativeRequests = List.unmodifiable(
         _nativeRequests(bases, gaps, spans, annotationGaps),
       ) {
    if (bases.isEmpty ||
        sides.isEmpty ||
        !maxWidth.isFinite ||
        maxWidth <= 0 ||
        maxWidth > 16384) {
      _invalid(ForumBodyRubyGroupFailure.geometry);
    }
    final scope = bases.first.content;
    final seen = Set<ForumBodyParagraphContent>.identity();
    var hasText = false;
    void check(ForumBodyParagraphContent content) {
      if (content.identity != scope.identity ||
          content.fontRevision != scope.fontRevision ||
          content.styleRevision != scope.styleRevision) {
        _invalid(ForumBodyRubyGroupFailure.scope);
      }
      if (content.layoutMode !=
              ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
          (!content.isSourceFree && !seen.add(content))) {
        _invalid(ForumBodyRubyGroupFailure.content);
      }
      hasText |= content.projection.text.isNotEmpty;
    }

    for (final base in bases) {
      check(base.content);
    }
    var previousGap = 0;
    for (final gap in gaps) {
      if (gap.beforeColumn <= 0 ||
          gap.beforeColumn >= bases.length ||
          gap.beforeColumn < previousGap ||
          gap.request.content.projection.text.isEmpty ||
          !gap.request.content.projection.text.runes.every(
            (rune) => rune == 9 || rune == 32,
          ) ||
          gap.request.content.isSourceFree) {
        _invalid(ForumBodyRubyGroupFailure.content);
      }
      previousGap = gap.beforeColumn;
      check(gap.request.content);
    }
    final lastEnd = <int, int>{};
    final adjacent = annotationGaps.isEmpty
        ? const <bool>[]
        : List.filled(spans.length, false);
    for (final (index, span) in spans.indexed) {
      if (span.startColumn < 0 ||
          span.endColumn > bases.length ||
          span.startColumn >= span.endColumn ||
          span.annotationIndex < 0 ||
          span.annotationIndex >= sides.length ||
          span.startColumn < (lastEnd[span.annotationIndex] ?? 0) ||
          !span.gap.isFinite ||
          span.gap < 0 ||
          span.gap > 16384) {
        _invalid(ForumBodyRubyGroupFailure.geometry);
      }
      if (annotationGaps.isNotEmpty) {
        adjacent[index] = lastEnd[span.annotationIndex] == span.startColumn;
      }
      lastEnd[span.annotationIndex] = span.endColumn;
      check(span.request.content);
    }
    var previousSpan = -1;
    for (final gap in annotationGaps) {
      if (gap.beforeSpanIndex < 0 ||
          gap.beforeSpanIndex >= spans.length ||
          gap.beforeSpanIndex < previousSpan ||
          !adjacent[gap.beforeSpanIndex] ||
          gap.request.content.projection.text.isEmpty ||
          gap.request.content.isSourceFree ||
          !gap.request.content.projection.text.runes.every(
            (r) => r == 9 || r == 32,
          ) ||
          !gap.gap.isFinite ||
          gap.gap < 0 ||
          gap.gap > 16384) {
        _invalid(ForumBodyRubyGroupFailure.content);
      }
      previousSpan = gap.beforeSpanIndex;
      check(gap.request.content);
    }
    if (!hasText) _invalid(ForumBodyRubyGroupFailure.content);
  }
  final List<ForumBodyTextRequest> bases;
  final List<ForumBodyRubySide> sides;
  final List<ForumBodyRubySpanRequest> spans;
  final List<ForumBodyRubyGapRequest> gaps;
  final List<ForumBodyRubyAnnotationGapRequest> annotationGaps;
  final List<ForumBodyTextRequest> nativeRequests;
  final TextDirection direction;
  final double maxWidth;
  int get nativeHandleCount => nativeRequests.length;

  ForumBodyRubySegmentRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubySegmentRequest(
    bases: [for (final base in bases) map(base)],
    gaps: [
      for (final gap in gaps)
        (beforeColumn: gap.beforeColumn, request: map(gap.request)),
    ],
    annotationGaps: [
      for (final gap in annotationGaps)
        (
          beforeSpanIndex: gap.beforeSpanIndex,
          request: map(gap.request),
          gap: gap.gap,
        ),
    ],
    sides: sides,
    spans: [
      for (final span in spans)
        (
          request: map(span.request),
          startColumn: span.startColumn,
          endColumn: span.endColumn,
          annotationIndex: span.annotationIndex,
          gap: span.gap,
        ),
    ],
    direction: direction,
    maxWidth: maxWidth,
  );
  static Never _invalid(ForumBodyRubyGroupFailure failure) =>
      throw ForumBodyRubyGroupException(failure);
}

Iterable<ForumBodyTextRequest> _nativeRequests(
  List<ForumBodyTextRequest> bases,
  List<ForumBodyRubyGapRequest> gaps,
  List<ForumBodyRubySpanRequest> spans,
  List<ForumBodyRubyAnnotationGapRequest> annotationGaps,
) sync* {
  var gap = 0;
  for (var column = 0; column < bases.length; column++) {
    while (gap < gaps.length && gaps[gap].beforeColumn == column) {
      yield gaps[gap++].request;
    }
    yield bases[column];
  }
  var annotationGap = 0;
  for (final (index, span) in spans.indexed) {
    while (annotationGap < annotationGaps.length &&
        annotationGaps[annotationGap].beforeSpanIndex == index) {
      yield annotationGaps[annotationGap++].request;
    }
    if (span.request.content.projection.text.isNotEmpty) yield span.request;
  }
}
