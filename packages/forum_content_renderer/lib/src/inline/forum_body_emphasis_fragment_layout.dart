part of 'forum_body_paragraph_frame.dart';

/// One current source binding and ONE prepared scene for complete paragraph
/// groups. All display/source offsets stay in the original whole paragraph.
final class ForumBodyEmphasisFragmentLayout implements ForumBodyTextLayout {
  ForumBodyEmphasisFragmentLayout._({
    required this.input,
    required ForumBodyParagraphLease source,
    required ForumBodyTextPictureLease picture,
    required List<ForumBodyParagraphRowView> rows,
    required List<ForumBodyParagraphLine> lines,
    required void Function() ensureOwner,
  }) : _source = source,
       _picture = picture,
       _rows = UnmodifiableListView(rows),
       lines = UnmodifiableListView(lines),
       _ensureOwner = ensureOwner;
  static const revision = 1;
  final ForumBodyEmphasisFragmentInput input;
  final List<ForumBodyParagraphLine> lines;
  List<ForumBodyParagraphRowView> _rows;
  ForumBodyParagraphLease? _source;
  ForumBodyTextPictureLease? _picture;
  void Function()? _ensureOwner;
  int get coverageStartUtf16 => input.coverageStartUtf16;
  int get coverageEndUtf16 => input.coverageEndUtf16;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_source,
    ?_picture,
  ];
  @override
  double get width => input.width;
  @override
  double get height => input.height;
  @override
  double get alphabeticBaseline => lines.first.baseline;
  @override
  HtmlDisplayTextProjection get projection =>
      input.paragraph.content.projection;
  @override
  bool get isDisposed =>
      _source?.isActive != true || _picture?.isActive != true;
  @override
  bool get isPaintPrepared => !isDisposed;
  void ensureActive() => _guard();
  void _guard() {
    if (isDisposed) throw StateError('Emphasis fragment is retired');
    _ensureOwner!();
    if (isDisposed) throw StateError('Emphasis fragment owner is retired');
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    _guard();
    _picture!.paint(canvas, offset);
  }

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _guard();
    _finiteAllocatedOffset(offset);
    final selected = input.selection, groups = input.paragraph.groups;
    final wholeY = offset.dy + selected.top;
    var low = selected.startGroup, high = selected.endGroup - 1;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (wholeY < groups[mid].top + groups[mid].height) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final group = groups[low];
    final local = _allocatedSourceAt(
      group.allocation,
      _rows[low - selected.startGroup],
      Offset(offset.dx, wholeY - group.top),
    );
    final display = group.startUtf16 + local.displayUtf16;
    var whole = projection.sourceAtUtf16(display);
    if (whole.sourceRune != local.sourceRune) {
      final upstream = projection.sourceAtUtf16(
        display,
        affinity: HtmlProjectionAffinity.upstream,
      );
      if (upstream.sourceRune == local.sourceRune) whole = upstream;
    }
    return HtmlProjectedSourcePosition(
      sourceRune: whole.sourceRune,
      displayUtf16: display,
      isExact:
          local.isExact &&
          whole.isExact &&
          local.sourceRune == whole.sourceRune,
    );
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) =>
      _boxes(startUtf16, endUtf16, paintedOnly: false);

  /// Unclipped native proof geometry; never hide overflow by clipping it to
  /// the fragment. Only confirmed unpainted native SPACE suffixes are omitted.
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) =>
      _boxes(startUtf16, endUtf16, paintedOnly: true);

  List<TextBox> _boxes(
    int startUtf16,
    int endUtf16, {
    required bool paintedOnly,
  }) {
    _guard();
    RangeError.checkValidRange(startUtf16, endUtf16, projection.text.length);
    final start = startUtf16.clamp(coverageStartUtf16, coverageEndUtf16),
        end = endUtf16.clamp(coverageStartUtf16, coverageEndUtf16);
    if (start >= end) return const [];
    final ranges = paintedOnly
        ? forumBodyPaintedTextRanges(input.paragraph.lines, start, end)
        : [TextRange(start: start, end: end)];
    final result = <TextBox>[];
    for (final range in ranges) {
      var low = input.selection.startGroup, high = input.selection.endGroup;
      while (low < high) {
        final mid = low + (high - low) ~/ 2;
        if (input.paragraph.groups[mid].endUtf16 <= range.start) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      for (var index = low; index < input.selection.endGroup; index++) {
        final group = input.paragraph.groups[index];
        if (group.endUtf16 <= range.start) continue;
        if (group.startUtf16 >= range.end) break;
        final from = range.start.clamp(group.startUtf16, group.endUtf16),
            to = range.end.clamp(group.startUtf16, group.endUtf16),
            row = _rows[index - input.selection.startGroup],
            offset = Offset(0, group.top - input.selection.top);
        for (final box in row.selectionBoxes(
          from - group.startUtf16,
          to - group.startUtf16,
        )) {
          final allocated = _allocatedBox(
            group.allocation,
            box,
            row.selector.originY,
          ).toRect().shift(offset);
          result.add(
            TextBox.fromLTRBD(
              allocated.left,
              allocated.top,
              allocated.right,
              allocated.bottom,
              box.direction,
            ),
          );
        }
      }
    }
    return List.unmodifiable(result);
  }

  void close() {
    final source = _source, picture = _picture;
    _source = null;
    _picture = null;
    _rows = const [];
    _ensureOwner = null;
    try {
      picture?.release();
    } finally {
      source?.release();
    }
  }
}
