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

/// Immutable original base/annotation requests for one unbroken component.
/// Native slots count empty base font struts, but never empty annotation glyphs.
/// Parent/source-window and complete-band retention remain page admission work.
final class ForumBodyRubySegmentRequest {
  ForumBodyRubySegmentRequest({
    required List<ForumBodyTextRequest> bases,
    required List<ForumBodyRubySide> sides,
    required List<ForumBodyRubySpanRequest> spans,
    this.direction = TextDirection.ltr,
    this.maxWidth = 16384,
  }) : bases = List.unmodifiable(bases),
       sides = List.unmodifiable(sides),
       spans = List.unmodifiable(spans),
       nativeRequests = List.unmodifiable([
         ...bases,
         for (final span in spans)
           if (span.request.content.projection.text.isNotEmpty) span.request,
       ]) {
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
    final lastEnd = <int, int>{};
    for (final span in spans) {
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
      lastEnd[span.annotationIndex] = span.endColumn;
      check(span.request.content);
    }
    if (!hasText) _invalid(ForumBodyRubyGroupFailure.content);
  }
  final List<ForumBodyTextRequest> bases;
  final List<ForumBodyRubySide> sides;
  final List<ForumBodyRubySpanRequest> spans;
  final List<ForumBodyTextRequest> nativeRequests;
  final TextDirection direction;
  final double maxWidth;
  int get nativeHandleCount => nativeRequests.length;

  ForumBodyRubySegmentRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubySegmentRequest(
    bases: [for (final base in bases) map(base)],
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
