import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Handles a page turn that ran past a chapter edge, returning whether the turn
/// was accepted and a switch is now in flight.
///
/// The boolean is load-bearing: the paged surface latches the gesture off while
/// a turn is in flight and only unlocks once the resulting entry request has been
/// applied and retired. A handler that silently declines (no neighbour, a switch
/// already running) would leave that lock waiting on a request that never
/// arrives, so declining must be reported.
typedef NovelReaderChapterTurnHandler =
    bool Function(NovelReaderChapterEdge edge);

/// Which end of a chapter a page turn is crossing.
enum NovelReaderChapterEdge {
  /// Before the first page: the reader is heading into the previous chapter.
  start,

  /// After the last page: the reader is heading into the next chapter.
  end,
}

/// Asks the paged surface to open a freshly switched chapter at one of its
/// edges instead of at the persisted reading position.
///
/// Turning forward can simply land on page 0, but turning *backward* has to
/// land on the previous chapter's **last** page, and that page index is unknown
/// until the chapter has been paginated. So the intent travels with the
/// transition and the surface resolves it once the plan is complete.
@immutable
class NovelReaderChapterEntryRequest {
  const NovelReaderChapterEntryRequest({
    required this.requestId,
    required this.episodeId,
    required this.edge,
  });

  final int requestId;
  final String episodeId;
  final NovelReaderChapterEdge edge;
}

/// Visual knobs for the boundary hint. Edit these values directly; nothing is
/// derived from them.
abstract final class NovelReaderChapterTurnHintLayout {
  static const double bottomInset = 12;
  static const double horizontalPadding = 12;
  static const double verticalPadding = 6;
  static const double cornerRadius = 10;
  static const double backgroundOpacity = 0.92;
}

/// Live state of an in-progress boundary drag, used to render the hint that
/// makes the gesture discoverable.
@immutable
class NovelReaderChapterTurnHint {
  const NovelReaderChapterTurnHint({
    required this.edge,
    required this.chapterTitle,
    required this.isReadyToCommit,
  });

  final NovelReaderChapterEdge edge;
  final String chapterTitle;

  /// True once the drag has passed the commit threshold, so the copy can switch
  /// from "keep pulling" to "release to go".
  final bool isReadyToCommit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is NovelReaderChapterTurnHint &&
        other.edge == edge &&
        other.chapterTitle == chapterTitle &&
        other.isReadyToCommit == isReadyToCommit;
  }

  @override
  int get hashCode => Object.hash(edge, chapterTitle, isReadyToCommit);
}

/// Turn-past-the-edge thresholds for paged mode.
///
/// Tuning guide: the constructor defaults are the knobs. [minCommitDistance]
/// keeps the gesture deliberate on small viewports and
/// [viewportCommitFraction] keeps it proportional on large ones; the effective
/// threshold is whichever is larger. Lower them for a lighter-feeling turn,
/// raise them if testers report accidental chapter switches.
///
/// Do not set [hintRevealFraction] to 1: the hint has to appear *before* the
/// commit threshold, otherwise the gesture stays undiscoverable.
@immutable
class NovelReaderChapterTurnPolicy {
  const NovelReaderChapterTurnPolicy({
    this.minCommitDistance = 44,
    this.viewportCommitFraction = 0.1,
    this.hintRevealFraction = 0.3,
  });

  /// Smallest drag past the edge that still commits a chapter turn.
  final double minCommitDistance;

  /// Commit distance expressed as a fraction of the scrollable extent.
  final double viewportCommitFraction;

  /// Fraction of the commit distance at which the boundary hint appears.
  final double hintRevealFraction;

  double commitDistanceFor(double viewportDimension) {
    if (!viewportDimension.isFinite || viewportDimension <= 0) {
      return minCommitDistance;
    }
    return math.max(
      minCommitDistance,
      viewportDimension * viewportCommitFraction,
    );
  }

  double hintRevealDistanceFor(double viewportDimension) {
    return commitDistanceFor(viewportDimension) * hintRevealFraction;
  }

  bool shouldCommit({
    required double overscrollDistance,
    required double viewportDimension,
  }) {
    return overscrollDistance >= commitDistanceFor(viewportDimension);
  }

  bool shouldRevealHint({
    required double overscrollDistance,
    required double viewportDimension,
  }) {
    return overscrollDistance >= hintRevealDistanceFor(viewportDimension);
  }
}
