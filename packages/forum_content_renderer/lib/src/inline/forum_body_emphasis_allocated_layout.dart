part of 'forum_body_emphasis_line_layout.dart';

void _finiteAllocatedOffset(Offset offset) {
  if (!offset.dx.isFinite || !offset.dy.isFinite) {
    throw ArgumentError.value(offset);
  }
}

HtmlProjectedSourcePosition _allocatedSourceAt(
  ForumBodyEmphasisRowAllocation allocation,
  ForumBodyParagraphRowView group,
  Offset offset,
) {
  final selected = _allocatedRowForY(allocation, offset.dy);
  final original = offset - selected.logicalOffset;
  final font = selected.physicalLine.fontBounds;
  // Keep hits in reserved space on the chosen row.
  final y = original.dy.clamp(font.top, font.bottom);
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
