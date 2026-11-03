part of 'forum_body_emphasis_line_layout.dart';

/// Current source binding plus one prepared allocated scene. Font phases and
/// marker leases have already retired; visible paint only replays the picture.
final class ForumBodyEmphasisAllocatedLayout implements ForumBodyTextLayout {
  ForumBodyEmphasisAllocatedLayout._({
    required this.allocation,
    required ForumBodyParagraphLease base,
    required ForumBodyParagraphRowView row,
    required ForumBodyTextPictureLease picture,
    required void Function() ensureOwner,
  }) : _base = base,
       _row = row,
       _picture = picture,
       _ensureOwner = ensureOwner;
  static const revision = 1;
  final ForumBodyEmphasisRowAllocation allocation;
  ForumBodyParagraphLease? _base;
  ForumBodyParagraphRowView? _row;
  ForumBodyTextPictureLease? _picture;
  void Function()? _ensureOwner;
  ForumBodyTextPictureInput get pictureInput {
    _guard();
    return _picture!.input;
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_base,
    ?_picture,
  ];
  @override
  double get width => allocation.width;
  @override
  double get height => allocation.height;
  @override
  double get alphabeticBaseline => allocation.alphabeticBaseline;
  Rect get fontBounds => allocation.fontBounds;
  @override
  HtmlDisplayTextProjection get projection =>
      allocation.source.input.content.projection;
  @override
  bool get isDisposed => _base?.isActive != true || _picture?.isActive != true;
  @override
  bool get isPaintPrepared => !isDisposed;
  void _guard() {
    if (isDisposed) throw StateError('Allocated emphasis is retired');
    _ensureOwner!();
    if (isDisposed) throw StateError('Allocated emphasis owner is retired');
  }

  @override
  void paint(Canvas canvas, Offset offset) {
    _guard();
    _picture!.paint(canvas, offset);
  }

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _guard();
    _finiteOffset(offset);
    return _allocatedSourceAt(allocation, _row!, offset);
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    _guard();
    final group = _row!;
    return List.unmodifiable([
      for (final box in group.selectionBoxes(startUtf16, endUtf16))
        _allocatedBox(allocation, box, group.selector.originY),
    ]);
  }

  static void _finiteOffset(Offset offset) {
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
  }

  void close() {
    final base = _base, picture = _picture;
    _base = null;
    _row = null;
    _picture = null;
    _ensureOwner = null;
    try {
      picture?.release();
    } finally {
      base?.release();
    }
  }
}

// Single-group and merged-fragment bindings use the same inverse geometry.
HtmlProjectedSourcePosition _allocatedSourceAt(
  ForumBodyEmphasisRowAllocation allocation,
  ForumBodyParagraphRowView group,
  Offset offset,
) {
  ForumBodyEmphasisAllocatedMark? chosen;
  var distance = double.infinity;
  for (final mark in allocation.marks) {
    if (!mark.fontBounds.contains(offset)) continue;
    final d = (mark.fontBounds.center - offset).distanceSquared;
    if (d < distance) {
      chosen = mark;
      distance = d;
    }
  }
  if (chosen != null) {
    final original = allocation.source.marks[chosen.markIndex];
    final unit = allocation.source.input.units[original.unitIndex];
    final source = allocation.source.input.content.projection.sourceAtUtf16(
      unit.governingUtf16,
    );
    return HtmlProjectedSourcePosition(
      sourceRune: source.sourceRune,
      displayUtf16: source.displayUtf16,
      isExact: false,
    );
  }
  final selected = _allocatedRowForY(allocation, offset.dy);
  final original =
      offset -
      Offset(0, selected.sourceTranslationY) -
      allocation.source.baseOffset;
  final font = selected.physicalLine.fontBounds;
  // Allocation may add much more space than native isolation (e.g. an
  // accessibility-scaled marker). Keep blank-area hits on the chosen row.
  final y = (original.dy + group.selector.originY).clamp(font.top, font.bottom);
  return group.sourceAt(Offset(original.dx, y - group.selector.originY));
}

ForumBodyEmphasisAllocatedRow _allocatedRowForY(
  ForumBodyEmphasisRowAllocation allocation,
  double y,
) {
  final rows = allocation.rows;
  var low = 0, high = rows.length - 1;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (y < rows[mid].flowBottom) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return rows[low];
}

TextBox _allocatedBox(
  ForumBodyEmphasisRowAllocation allocation,
  TextBox box,
  double origin,
) {
  final rect = box.toRect().shift(Offset(0, origin)), rows = allocation.rows;
  var low = 0, high = rows.length - 1;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (rect.bottom <= rows[mid].physicalLine.selector.clipBottom) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  final row = rows[low], clip = row.physicalLine.selector;
  if (rect.top < clip.clipTop ||
      rect.bottom > clip.clipBottom ||
      (rect.isEmpty && low + 1 < rows.length && rect.top == clip.clipBottom)) {
    throw const ForumBodyEmphasisLineException(
      ForumBodyEmphasisLineFailure.metrics,
    );
  }
  final placed = rect.shift(row.logicalOffset);
  return TextBox.fromLTRBD(
    placed.left,
    placed.top,
    placed.right,
    placed.bottom,
    box.direction,
  );
}
