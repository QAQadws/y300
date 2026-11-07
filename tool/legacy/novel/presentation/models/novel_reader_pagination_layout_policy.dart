import 'package:flutter/foundation.dart';

enum NovelReaderPaginationMeasurePolicy {
  textPainter,
  htmlRendererRange,
  htmlRendererWholeAtom,
}

enum NovelReaderPaginationSplitPolicy { lineRanges, domBoundaries, none }

enum NovelReaderPaginationPlacementPolicy { flow, dedicatedPage }

enum NovelReaderPaginationOverflowPolicy {
  minimumTextFragment,
  innerScroll,
  fallbackToVertical,
}

/// Describes what a classified atom can do without deciding how the current
/// production composer executes that capability.
@immutable
final class NovelReaderPaginationLayoutPolicy {
  const NovelReaderPaginationLayoutPolicy({
    required this.measure,
    required this.split,
    required this.placement,
    required this.overflow,
    required this.keepPageOpenAfterAppend,
  });

  final NovelReaderPaginationMeasurePolicy measure;
  final NovelReaderPaginationSplitPolicy split;
  final NovelReaderPaginationPlacementPolicy placement;
  final NovelReaderPaginationOverflowPolicy overflow;
  final bool keepPageOpenAfterAppend;

  bool get isBreakable => split != NovelReaderPaginationSplitPolicy.none;
  bool get isDedicated =>
      placement == NovelReaderPaginationPlacementPolicy.dedicatedPage;

  @override
  bool operator ==(Object other) {
    return other is NovelReaderPaginationLayoutPolicy &&
        other.measure == measure &&
        other.split == split &&
        other.placement == placement &&
        other.overflow == overflow &&
        other.keepPageOpenAfterAppend == keepPageOpenAfterAppend;
  }

  @override
  int get hashCode =>
      Object.hash(measure, split, placement, overflow, keepPageOpenAfterAppend);
}
