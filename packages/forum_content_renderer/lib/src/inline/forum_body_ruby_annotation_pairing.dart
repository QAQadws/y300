import '../style/forum_body_style_options.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_annotation_input.dart';
import 'forum_body_ruby_content.dart';

/// A single original annotation box and the half-open base-column interval it
/// owns. Source, styles and text identity stay with that ONE box across a span.
final class ForumBodyRubyAnnotationSpan {
  const ForumBodyRubyAnnotationSpan._({
    required this.box,
    required this.startColumn,
    required this.endColumn,
  });
  final ForumBodyRubyAnnotationBoxInput box;
  final int startColumn;
  final int endColumn;
  bool get isMultiColumn => endColumn - startColumn > 1;
}

final class ForumBodyRubyPairedAnnotationLevel {
  ForumBodyRubyPairedAnnotationLevel._({
    required this.side,
    required List<ForumBodyRubyAnnotationSpan> spans,
    required List<ForumBodyRubyPairedAnnotationGap> gaps,
  }) : spans = List.unmodifiable(spans),
       gaps = gaps.isEmpty ? const [] : List.unmodifiable(gaps);
  final ForumBodyRubySide side;
  final List<ForumBodyRubyAnnotationSpan> spans;
  final List<ForumBodyRubyPairedAnnotationGap> gaps;
}

/// One actual annotation-level context at a logical column edge. The adjacent
/// spans are original objects; no anonymous RT or base source is manufactured.
final class ForumBodyRubyPairedAnnotationGap {
  const ForumBodyRubyPairedAnnotationGap._({
    required this.content,
    required this.beforeColumn,
    required this.previous,
    required this.next,
  });
  final ForumBodyParagraphContent content;
  final int beforeColumn;
  final ForumBodyRubyAnnotationSpan previous;
  final ForumBodyRubyAnnotationSpan next;
}

typedef ForumBodyRubyColumnRange = ({int startColumn, int endColumn});

/// Pure unit pairing after anonymous-box generation, before glyph measurement.
/// Empty/missing positions are not invented source boxes. An entire segment's
/// base count includes anonymous bases needed by any longer annotation level.
final class ForumBodyRubyAnnotationPairing {
  factory ForumBodyRubyAnnotationPairing({
    required ForumBodyRubyGroupContent group,
    required int baseColumnCount,
  }) {
    if (baseColumnCount < 0) {
      throw ArgumentError.value(baseColumnCount, 'baseColumnCount');
    }
    final inputs = resolveForumBodyRubyAnnotationInputs(group);
    var columnCount = baseColumnCount;
    for (final level in inputs) {
      if (level.boxes.length > columnCount) columnCount = level.boxes.length;
    }
    var annotatedColumnCount = 0;
    var hasMultiColumnSpans = false;
    final levels = <ForumBodyRubyPairedAnnotationLevel>[];
    for (final level in inputs) {
      final spans = <ForumBodyRubyAnnotationSpan>[];
      final spansSegment =
          level.boxes.length == 1 &&
          level.boxes.single is ForumBodyRubyAnonymousAnnotationInput;
      for (final (index, box) in level.boxes.indexed) {
        final end = spansSegment ? columnCount : index + 1;
        if (end > annotatedColumnCount) annotatedColumnCount = end;
        final span = ForumBodyRubyAnnotationSpan._(
          box: box,
          startColumn: index,
          endColumn: end,
        );
        hasMultiColumnSpans |= span.isMultiColumn;
        spans.add(span);
      }
      final gaps = level.gaps.isEmpty
          ? const <ForumBodyRubyPairedAnnotationGap>[]
          : [
              for (final gap in level.gaps)
                ForumBodyRubyPairedAnnotationGap._(
                  content: gap.content,
                  beforeColumn: spans[gap.beforeBox].startColumn,
                  previous: spans[gap.beforeBox - 1],
                  next: spans[gap.beforeBox],
                ),
            ];
      levels.add(
        ForumBodyRubyPairedAnnotationLevel._(
          side: level.side,
          spans: spans,
          gaps: gaps,
        ),
      );
    }
    return ForumBodyRubyAnnotationPairing._(
      columnCount: columnCount,
      annotatedColumnCount: annotatedColumnCount,
      levels: levels,
      hasMultiColumnSpans: hasMultiColumnSpans,
    );
  }

  ForumBodyRubyAnnotationPairing._({
    required this.columnCount,
    required this.annotatedColumnCount,
    required List<ForumBodyRubyPairedAnnotationLevel> levels,
    required this.hasMultiColumnSpans,
  }) : levels = List.unmodifiable(levels);

  final int columnCount;
  final int annotatedColumnCount;
  final List<ForumBodyRubyPairedAnnotationLevel> levels;
  final bool hasMultiColumnSpans;

  /// Spanning closures only: actual break opportunity, whitespace trimming,
  /// native fit and source/coverage admission still belong to the layout path.
  late final List<ForumBodyRubyColumnRange> columnRanges = _columnRanges();
  bool get hasAnnotationGaps => levels.any((level) => level.gaps.isNotEmpty);

  List<ForumBodyRubyColumnRange> _columnRanges() {
    // Only real spanning annotations close a range. Compute lazily so the
    // current column planner does not allocate unused boundary vectors.
    final blocked = List.filled(columnCount + 1, 0);
    for (final level in levels) {
      for (final span in level.spans) {
        if (!span.isMultiColumn) continue;
        blocked[span.startColumn + 1]++;
        blocked[span.endColumn]--;
      }
    }
    final result = <ForumBodyRubyColumnRange>[];
    var depth = 0;
    var start = 0;
    for (var edge = 1; edge < columnCount; edge++) {
      depth += blocked[edge];
      if (depth == 0) {
        result.add((startColumn: start, endColumn: edge));
        start = edge;
      }
    }
    if (columnCount > 0) {
      result.add((startColumn: start, endColumn: columnCount));
    }
    return List.unmodifiable(result);
  }
}
