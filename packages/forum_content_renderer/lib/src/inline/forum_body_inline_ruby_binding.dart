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

  /// True when [ensureActive] can call into an external owner.
  bool get checksExternalOwner => false;
  void ensureActive() {
    if (!isActive) throw StateError('Inline ruby binding is retired');
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases;
  void paint(Canvas canvas, Offset offset);
  _RubySourceHit sourceAt(Offset point);
  List<TextBox> selectionBoxes(int start, int end);
  List<TextBox> glyphBoxes(int start, int end) => selectionBoxes(start, end);
  void close();
}

final class _IntrinsicInlineBinding extends _RubyBinding {
  const _IntrinsicInlineBinding(this.view, this.windows);
  final ForumBodyInlineParagraphView view;
  final Map<ForumBodyInlineContext, ForumBodyInlineContext> windows;
  @override
  Size get size => Size(view.width, view.height);
  @override
  double get baseline => view.lines.single.baseline;
  @override
  bool get isActive => view.isActive;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => view.nativeLeases;
  @override
  void paint(Canvas canvas, Offset offset) => view.paint(canvas, offset);
  @override
  _RubySourceHit sourceAt(Offset point) {
    final hit = view.sourceHitAt(point);
    final child =
        hit.window ??
        view.content.contexts.firstWhere(
          (c) =>
              c.startUtf16 <= hit.position.displayUtf16 &&
              c.endUtf16 >= hit.position.displayUtf16,
        );
    return (
      window: windows[child]!,
      position: HtmlProjectedSourcePosition(
        sourceRune: hit.position.sourceRune,
        displayUtf16: hit.position.displayUtf16 - child.startUtf16,
        isExact: hit.window != null && hit.position.isExact,
      ),
    );
  }

  List<TextBox> _boxes(int start, int end, bool glyphs) => [
    for (final pair in windows.entries)
      ..._selectRubyWindow(
        pair.value,
        start,
        end,
        (from, to) => glyphs
            ? view.glyphBoxes(
                pair.key.startUtf16 + from,
                pair.key.startUtf16 + to,
              )
            : view.selectionBoxes(
                pair.key.startUtf16 + from,
                pair.key.startUtf16 + to,
                clipToView: false,
              ),
      ),
  ];
  @override
  List<TextBox> selectionBoxes(int start, int end) => _boxes(start, end, false);
  @override
  List<TextBox> glyphBoxes(int start, int end) => _boxes(start, end, true);
  @override
  void close() => view.close();
}

final class _BaselineTextBinding extends _RubyBinding {
  const _BaselineTextBinding(this.text, this.window);
  final ForumBodyTextBaselineLayout text;
  final ForumBodyInlineContext window;
  @override
  Size get size => text.metrics.size;
  @override
  double get baseline => text.metrics.baseline;
  @override
  bool get isActive => !text.isDisposed;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [text.lease];
  @override
  void paint(Canvas canvas, Offset offset) => text.paint(canvas, offset);
  @override
  _RubySourceHit sourceAt(Offset point) =>
      (window: window, position: text.sourceAt(point));
  @override
  List<TextBox> selectionBoxes(int start, int end) =>
      _selectRubyWindow(window, start, end, text.selectionBoxes);
  @override
  void close() => text.close();
}

/// The complete scene already qualifies actual glyphs and markers. This second
/// binding associates each original current source with its real parent window.
final class _RubyRootFrameBinding extends _RubyBinding {
  const _RubyRootFrameBinding(this.child, this.frame, this.rowAllocation);
  final _RubyBinding child;
  final ForumBodyRubyAtomFrame frame;
  final Rect rowAllocation;
  bool hitsOuterLeading(Offset point) =>
      rowAllocation.contains(point) && !(Offset.zero & size).contains(point);
  Offset get _offset => frame.childOffset;
  @override
  Size get size => frame.size;
  @override
  double get baseline => frame.baseline;
  @override
  bool get isActive => child.isActive;
  @override
  bool get checksExternalOwner => child.checksExternalOwner;
  @override
  void ensureActive() => child.ensureActive();
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      child.nativeLeases;
  @override
  void paint(Canvas canvas, Offset offset) =>
      child.paint(canvas, offset + _offset);
  @override
  _RubySourceHit sourceAt(Offset point) {
    final local = point - _offset;
    final hit = child.sourceAt(local);
    if (frame.childBounds.contains(local)) return hit;
    // Root leading is allocation only. A clamped child caret cannot prove a
    // glyph/source hit at an unpainted point in that newly reserved area.
    return (
      window: hit.window,
      position: HtmlProjectedSourcePosition(
        sourceRune: hit.position.sourceRune,
        displayUtf16: hit.position.displayUtf16,
        isExact: false,
      ),
    );
  }

  @override
  List<TextBox> selectionBoxes(int start, int end) => [
    for (final box in child.selectionBoxes(start, end))
      TextBox.fromLTRBD(
        box.left + _offset.dx,
        box.top + _offset.dy,
        box.right + _offset.dx,
        box.bottom + _offset.dy,
        box.direction,
      ),
  ];
  @override
  List<TextBox> glyphBoxes(int start, int end) => [
    for (final box in child.glyphBoxes(start, end))
      TextBox.fromLTRBD(
        box.left + _offset.dx,
        box.top + _offset.dy,
        box.right + _offset.dx,
        box.bottom + _offset.dy,
        box.direction,
      ),
  ];
  @override
  void close() => child.close();
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
