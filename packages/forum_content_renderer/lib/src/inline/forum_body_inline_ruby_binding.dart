part of 'forum_body_inline_paragraph_view.dart';

typedef _RubySourceHit = ({
  ForumBodyInlineContext window,
  HtmlProjectedSourcePosition position,
});

/// Source windows bind current members, never equal text or cached snapshots.
/// These adapters borrow already-transferred visible ownership and do not shape.
sealed class _RubyBinding {
  const _RubyBinding();
  Size get size;
  double get baseline;
  bool get isActive;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases;
  void paint(Canvas canvas, Offset offset);
  _RubySourceHit sourceAt(Offset point);
  List<TextBox> selectionBoxes(int start, int end);
  void close();
}

final class _RubySpaceBinding extends _RubyBinding {
  const _RubySpaceBinding(this.space, this.windows);
  final ForumBodyRubySoftSpaceLayout space;
  final List<ForumBodyInlineContext> windows;
  @override
  Size get size => space.size;
  @override
  double get baseline => space.baseline;
  @override
  bool get isActive => space.isActive;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      space.nativeLeases;
  @override
  void paint(Canvas canvas, Offset offset) => space.paint(canvas, offset);
  @override
  _RubySourceHit sourceAt(Offset point) {
    final hit = space.sourceAt(point);
    return (window: windows[hit.memberIndex], position: hit.position);
  }

  @override
  List<TextBox> selectionBoxes(int start, int end) => [
    for (final (index, window) in windows.indexed)
      ..._selectRubyWindow(
        window,
        start,
        end,
        (from, to) => space.selectionBoxes(
          memberIndex: index,
          startUtf16: from,
          endUtf16: to,
        ),
      ),
  ];
  @override
  void close() => space.close();
}

final class _RubyColumnWindows {
  const _RubyColumnWindows(this.base, this.annotations);
  final ForumBodyInlineContext base;
  final List<ForumBodyInlineContext?> annotations;
  ForumBodyInlineContext forHit(ForumBodyRubyHit hit) =>
      hit.part == ForumBodyRubyPart.base
      ? base
      : annotations[hit.annotationIndex!]!;
}

List<TextBox> _selectRubyWindow(
  ForumBodyInlineContext? window,
  int start,
  int end,
  List<TextBox> Function(int from, int to) select,
) {
  if (window == null) return const [];
  final from =
      start.clamp(window.startUtf16, window.endUtf16) - window.startUtf16;
  final to = end.clamp(window.startUtf16, window.endUtf16) - window.startUtf16;
  return from < to ? select(from, to) : const [];
}

final class _RubyColumnBinding extends _RubyBinding {
  const _RubyColumnBinding(this.group, this.windows);
  final ForumBodyRubyGroupLayout group;
  final _RubyColumnWindows windows;
  @override
  Size get size => group.size;
  @override
  double get baseline => group.baseline;
  @override
  bool get isActive => group.isActive;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      group.nativeLeases;
  @override
  void paint(Canvas canvas, Offset offset) => group.paint(canvas, offset);
  @override
  _RubySourceHit sourceAt(Offset point) {
    final hit = group.sourceAt(point);
    return (window: windows.forHit(hit), position: hit.position);
  }

  @override
  List<TextBox> selectionBoxes(int start, int end) => [
    ..._selectRubyWindow(
      windows.base,
      start,
      end,
      (from, to) => group.selectionBoxes(
        part: ForumBodyRubyPart.base,
        startUtf16: from,
        endUtf16: to,
      ),
    ),
    for (final (rank, window) in windows.annotations.indexed)
      ..._selectRubyWindow(
        window,
        start,
        end,
        (from, to) => group.selectionBoxes(
          part: ForumBodyRubyPart.annotation,
          annotationIndex: rank,
          startUtf16: from,
          endUtf16: to,
        ),
      ),
  ];
  @override
  void close() => group.close();
}

final class _RubySegmentBinding extends _RubyBinding {
  const _RubySegmentBinding(
    this.segment,
    this.columns,
    this.spans,
    this.gaps,
    this.annotationGaps,
  );
  final ForumBodyRubySegmentLayout segment;
  final List<_RubyColumnWindows> columns;
  final List<ForumBodyInlineContext?> spans;
  final List<ForumBodyInlineContext> gaps;
  final List<ForumBodyInlineContext> annotationGaps;
  @override
  Size get size => segment.size;
  @override
  double get baseline => segment.baseline;
  @override
  bool get isActive => segment.isActive;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      segment.nativeLeases;
  @override
  void paint(Canvas canvas, Offset offset) => segment.paint(canvas, offset);
  @override
  _RubySourceHit sourceAt(Offset point) {
    final hit = segment.sourceAt(point);
    final window = hit.annotationGapIndex != null
        ? annotationGaps[hit.annotationGapIndex!]
        : hit.gapIndex != null
        ? gaps[hit.gapIndex!]
        : hit.spanIndex != null
        ? spans[hit.spanIndex!]!
        : columns[hit.columnIndex!].forHit(hit.columnHit!);
    return (window: window, position: hit.position);
  }

  @override
  List<TextBox> selectionBoxes(int start, int end) => [
    for (final (index, column) in columns.indexed) ...[
      ..._selectRubyWindow(
        column.base,
        start,
        end,
        (from, to) => segment.selectionBoxesForColumn(
          columnIndex: index,
          part: ForumBodyRubyPart.base,
          startUtf16: from,
          endUtf16: to,
        ),
      ),
      for (final (rank, window) in column.annotations.indexed)
        ..._selectRubyWindow(
          window,
          start,
          end,
          (from, to) => segment.selectionBoxesForColumn(
            columnIndex: index,
            part: ForumBodyRubyPart.annotation,
            annotationIndex: rank,
            startUtf16: from,
            endUtf16: to,
          ),
        ),
    ],
    for (final (index, window) in spans.indexed)
      ..._selectRubyWindow(
        window,
        start,
        end,
        (from, to) => segment.selectionBoxesForSpan(
          spanIndex: index,
          startUtf16: from,
          endUtf16: to,
        ),
      ),
    for (final (index, window) in gaps.indexed)
      ..._selectRubyWindow(
        window,
        start,
        end,
        (from, to) => segment.selectionBoxesForGap(
          gapIndex: index,
          startUtf16: from,
          endUtf16: to,
        ),
      ),
    for (final (index, window) in annotationGaps.indexed)
      ..._selectRubyWindow(
        window,
        start,
        end,
        (from, to) => segment.selectionBoxesForAnnotationGap(
          gapIndex: index,
          startUtf16: from,
          endUtf16: to,
        ),
      ),
  ];
  @override
  void close() => segment.close();
}
