import 'package:flutter/painting.dart';

import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_ruby_tree_metrics_preparation.dart';

/// The real structural role of one child, not a source/DOM coordinate. Indices
/// address the corresponding original group's or segment's immutable list.
enum ForumBodyRubyTreeBranch {
  base,
  annotation,
  frame,
  gap,
  span,
  annotationGap,
  fence,
}

/// One edge in the measured tree. [offset] is relative to the parent's child
/// coordinate system, after its enclosing font frame's two-dimensional shift.
final class ForumBodyRubyTreeChildGeometry {
  const ForumBodyRubyTreeChildGeometry({
    required this.node,
    required this.branch,
    required this.index,
    required this.offset,
  });
  final int node;
  final ForumBodyRubyTreeBranch branch;
  final int index;
  final Offset offset;
}

/// Constant-time enumeration includes empty annotation slots. Callers advance
/// one slot per work part instead of scanning through absent ranks in a loop.
int forumBodyRubyTreeChildSlotCount(ForumBodyRubyTreeContainer node) =>
    switch (node) {
      ForumBodyRubyTreeGroup() => 1 + node.annotations.length,
      ForumBodyRubyTreeSegment() => node.children.length,
      ForumBodyRubyTreeFrame() => 1,
      ForumBodyRubyTreeInline() => 0,
    };

ForumBodyRubyTreeChildGeometry? forumBodyRubyTreeChildGeometryAt(
  ForumBodyRubyTreeContainer node,
  ForumBodyRubyTreeContainerMetrics metrics,
  int slot,
) {
  RangeError.checkValidIndex(
    slot,
    node,
    'slot',
    forumBodyRubyTreeChildSlotCount(node),
  );
  switch (node) {
    case ForumBodyRubyTreeGroup():
      if (slot == 0) {
        return ForumBodyRubyTreeChildGeometry(
          node: node.base,
          branch: ForumBodyRubyTreeBranch.base,
          index: 0,
          offset: metrics.group!.baseOffset,
        );
      }
      final rank = slot - 1, child = node.annotations[rank].child;
      return child == null
          ? null
          : ForumBodyRubyTreeChildGeometry(
              node: child,
              branch: ForumBodyRubyTreeBranch.annotation,
              index: rank,
              offset: metrics.group!.annotations[rank].offset,
            );
    case ForumBodyRubyTreeFrame():
      return ForumBodyRubyTreeChildGeometry(
        node: node.child,
        branch: ForumBodyRubyTreeBranch.frame,
        index: 0,
        offset: Offset.zero,
      );
    case ForumBodyRubyTreeSegment():
      final child = node.children[slot], segment = metrics.segment!;
      final (branch, offset) = switch (child.kind) {
        ForumBodyRubyTreeSegmentChildKind.base => (
          ForumBodyRubyTreeBranch.base,
          segment.columnOffsets[child.index] +
              segment.columns[child.index].baseOffset,
        ),
        ForumBodyRubyTreeSegmentChildKind.gap => (
          ForumBodyRubyTreeBranch.gap,
          segment.gaps[child.index].offset +
              segment.gaps[child.index].font.baseOffset,
        ),
        ForumBodyRubyTreeSegmentChildKind.span => (
          ForumBodyRubyTreeBranch.span,
          segment.spans[child.index].offset,
        ),
        ForumBodyRubyTreeSegmentChildKind.annotationGap => (
          ForumBodyRubyTreeBranch.annotationGap,
          segment.annotationGaps[child.index].offset,
        ),
        ForumBodyRubyTreeSegmentChildKind.fence => (
          ForumBodyRubyTreeBranch.fence,
          _fenceOffset(segment, node.fences[child.index]),
        ),
      };
      return ForumBodyRubyTreeChildGeometry(
        node: child.node,
        branch: branch,
        index: child.index,
        offset: offset,
      );
    case ForumBodyRubyTreeInline():
      throw StateError('Inline children belong to their actual native parent');
  }
}

Offset _fenceOffset(
  ForumBodyRubySegmentMetrics segment,
  ForumBodyRubyTreeSegmentFence fence,
) {
  final atEnd = fence.beforeColumn == segment.columns.length;
  final rtl = segment.direction == TextDirection.rtl;
  final x = atEnd
      ? (rtl ? 0.0 : segment.size.width)
      : segment.columnLefts[fence.beforeColumn] +
            (rtl ? segment.columnWidths[fence.beforeColumn] : 0);
  final y = fence.rank == null
      ? segment.baseline
      : segment.columns.first.annotations[fence.rank!].bandTop;
  return Offset(x, y);
}

/// Original glyph-tree coordinates, before any final marker envelope. Parent
/// links share immutable prefixes; entering a child does not copy its ancestry.
final class ForumBodyRubyTreeNodePosition {
  const ForumBodyRubyTreeNodePosition({
    required this.id,
    required this.origin,
    required this.contentOrigin,
    required this.parent,
    required this.edge,
  });
  final int id;
  final Offset origin;
  final Offset contentOrigin;
  final ForumBodyRubyTreeNodePosition? parent;
  final ForumBodyRubyTreeChildGeometry? edge;
}
