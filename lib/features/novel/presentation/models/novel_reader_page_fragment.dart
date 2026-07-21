import 'package:flutter/foundation.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';

enum NovelReaderPageOverflowState { none, atomicWidget, minimumTextFragment }

@immutable
class NovelReaderPageAnchorRange {
  const NovelReaderPageAnchorRange({required this.start, required this.end});

  final NovelReaderTextAnchor start;
  final NovelReaderTextAnchor end;

  @override
  bool operator ==(Object other) {
    return other is NovelReaderPageAnchorRange &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

@immutable
class NovelReaderPageFragment {
  const NovelReaderPageFragment({
    required this.index,
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.imageIndices,
    this.anchorRanges = const <NovelReaderPageAnchorRange>[],
    this.overflowState = NovelReaderPageOverflowState.none,
    this.requiresInnerScroll = false,
    this.usedHeight = 0,
    this.availableHeight = 0,
    this.gapReason = NovelReaderPageGapReason.none,
    this.containsIsolatedImage = false,
    this.isDedicatedContentPage = false,
  });

  final int index;
  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;

  /// Includes anchors for units fully contained between the page edges. The
  /// edge anchors remain available for compatibility with older plans.
  final List<NovelReaderPageAnchorRange> anchorRanges;

  /// These are the indexes from the prepared chapter's whole-document image
  /// sequence. They must never be renumbered when a page is created.
  final List<int> imageIndices;
  final NovelReaderPageOverflowState overflowState;
  final bool requiresInnerScroll;
  final double usedHeight;
  final double availableHeight;
  final NovelReaderPageGapReason gapReason;
  final bool containsIsolatedImage;
  final bool isDedicatedContentPage;

  bool get hasOverflow => overflowState != NovelReaderPageOverflowState.none;

  double get gapHeight => availableHeight <= 0
      ? 0
      : (availableHeight - usedHeight).clamp(0.0, availableHeight);

  double get fullness => availableHeight <= 0
      ? 0
      : (usedHeight / availableHeight).clamp(0.0, double.infinity);

  @override
  String toString() => 'NovelReaderPageFragment($index, $overflowState)';

  @override
  bool operator ==(Object other) {
    return other is NovelReaderPageFragment &&
        other.index == index &&
        other.html == html &&
        other.startAnchor == startAnchor &&
        other.endAnchor == endAnchor &&
        listEquals(other.anchorRanges, anchorRanges) &&
        listEquals(other.imageIndices, imageIndices) &&
        other.overflowState == overflowState &&
        other.requiresInnerScroll == requiresInnerScroll &&
        other.usedHeight == usedHeight &&
        other.availableHeight == availableHeight &&
        other.gapReason == gapReason &&
        other.containsIsolatedImage == containsIsolatedImage &&
        other.isDedicatedContentPage == isDedicatedContentPage;
  }

  @override
  int get hashCode => Object.hash(
    index,
    html,
    startAnchor,
    endAnchor,
    Object.hashAll(anchorRanges),
    Object.hashAll(imageIndices),
    overflowState,
    requiresInnerScroll,
    usedHeight,
    availableHeight,
    gapReason,
    containsIsolatedImage,
    isDedicatedContentPage,
  );
}
