import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';

enum NovelReaderPageOverflowState { none, atomicWidget, minimumTextFragment }

@immutable
class NovelReaderPageFragment {
  const NovelReaderPageFragment({
    required this.index,
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.imageIndices,
    this.overflowState = NovelReaderPageOverflowState.none,
    this.requiresInnerScroll = false,
  });

  final int index;
  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;

  /// These are the indexes from the prepared chapter's whole-document image
  /// sequence. They must never be renumbered when a page is created.
  final List<int> imageIndices;
  final NovelReaderPageOverflowState overflowState;
  final bool requiresInnerScroll;

  bool get hasOverflow => overflowState != NovelReaderPageOverflowState.none;

  @override
  String toString() => 'NovelReaderPageFragment($index, $overflowState)';

  @override
  bool operator ==(Object other) {
    return other is NovelReaderPageFragment &&
        other.index == index &&
        other.html == html &&
        other.startAnchor == startAnchor &&
        other.endAnchor == endAnchor &&
        listEquals(other.imageIndices, imageIndices) &&
        other.overflowState == overflowState &&
        other.requiresInnerScroll == requiresInnerScroll;
  }

  @override
  int get hashCode => Object.hash(
    index,
    html,
    startAnchor,
    endAnchor,
    Object.hashAll(imageIndices),
    overflowState,
    requiresInnerScroll,
  );
}
