part of 'forum_body_ruby_tree_metrics_preparation.dart';

/// Native measurements already belong to the postorder tree. Convert one real
/// child/rank at a time, then use the SAME column/span composition as flat ruby.
final class _TreeSegmentMetricsWork {
  _TreeSegmentMetricsWork(this.input, this.nodes, this.maxWidth);
  final ForumBodyRubyTreeSegment input;
  final List<ForumBodyRubyTreeNodeMetrics> nodes;
  final double maxWidth;
  final columns = <ForumBodyRubyGroupMetrics>[];
  final gaps = <ForumBodyRubyMeasuredGap>[];
  final spans = <ForumBodyRubyMeasuredSpan>[];
  final annotationGaps = <ForumBodyRubyMeasuredAnnotationGap>[];
  ForumBodyRubyGroupGeometry? column;
  ForumBodyRubySegmentComposition? composition;
  int rank = -1;
  bool closed = false;
  ForumBodyRubySegmentMetrics? result;
  bool get isReady => result != null;

  void advance() {
    if (closed || isReady) throw StateError('Tree segment metrics are retired');
    if (columns.length < input.bases.length ||
        gaps.length < input.gaps.length) {
      final gap = columns.length == input.bases.length;
      final id = gap
          ? input.gaps[gaps.length].child
          : input.bases[columns.length];
      if (column == null) {
        column = ForumBodyRubyGroupGeometry(
          annotations: [
            for (final side in input.sides)
              (hasAnnotation: false, gap: 0.0, side: side),
          ],
          maxWidth: maxWidth,
        );
      } else if (rank == -1) {
        column!.addBase(nodes[id].box!);
        rank = 0;
      } else if (rank < input.sides.length) {
        column!.addAnnotation(null);
        rank++;
      } else if (!column!.isReady) {
        column!.advance(maxParts: 1);
      } else {
        final value = column!.takeMetrics();
        column!.close();
        column = null;
        rank = -1;
        if (gap) {
          gaps.add(
            ForumBodyRubyMeasuredGap(
              beforeColumn: input.gaps[gaps.length].beforeColumn,
              font: value,
            ),
          );
        } else {
          columns.add(value);
        }
      }
      return;
    }
    if (spans.length < input.spans.length) {
      final target = input.spans[spans.length];
      spans.add(
        ForumBodyRubyMeasuredSpan(
          startColumn: target.startColumn,
          endColumn: target.endColumn,
          annotationIndex: target.rank,
          annotation: ForumBodyRubyAnnotationMetrics.fromChild(
            child: nodes[target.child].box,
            side: input.sides[target.rank],
          ),
        ),
      );
      return;
    }
    if (annotationGaps.length < input.annotationGaps.length) {
      final gap = input.annotationGaps[annotationGaps.length];
      final target = input.spans[gap.beforeSpan];
      annotationGaps.add(
        ForumBodyRubyMeasuredAnnotationGap(
          beforeColumn: target.startColumn,
          annotationIndex: target.rank,
          annotation: ForumBodyRubyAnnotationMetrics.fromChild(
            child: nodes[gap.child].box!,
            side: input.sides[target.rank],
          ),
        ),
      );
      return;
    }
    final work = composition ??= ForumBodyRubySegmentComposition(
      columns: columns,
      spans: spans,
      gaps: gaps,
      annotationGaps: annotationGaps,
      direction: input.group.style.textDirection,
      maxWidth: maxWidth,
    );
    if (!work.isComplete) {
      work.advance(maxParts: 1);
    } else {
      result = work.result;
      composition = null;
    }
  }

  void close() {
    closed = true;
    column?.close();
    column = null;
    composition = null;
  }
}
