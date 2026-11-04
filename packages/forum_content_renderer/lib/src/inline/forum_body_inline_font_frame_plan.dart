import 'dart:collection';

import 'package:flutter/painting.dart';

import '../flow/forum_body_inline_flow_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_inline_emphasis_parent_preparation.dart';
import 'forum_body_inline_emphasis_isolation_preparation.dart';
import 'forum_body_inline_emphasis_row_allocation.dart';
import 'forum_body_inline_emphasis_paint_preparation.dart';
import 'forum_body_inline_emphasis_paint_reference.dart';
import 'forum_body_inline_paint_row.dart';

part 'forum_body_inline_font_frame_preparation.dart';

/// A pure wrapping-text allocation. Its existing ruby/text children keep their
/// actual source roles; no parent decoration mark is introduced. Keys describe
/// drawing inputs, never permission to use an old source or native resource.
final class ForumBodyInlineFontFramePlan {
  ForumBodyInlineFontFramePlan._(
    this.source,
    this.allocation,
    this.paintReference,
    List<ForumBodyParagraphLine> lines,
    List<List<ForumBodyTextPictureCommand>> parentCommands,
  ) : lines = UnmodifiableListView(lines),
      _parentCommands = UnmodifiableListView(parentCommands);

  static const revision = 1;
  final ForumBodyInlinePlanInput source;
  final ForumBodyInlineEmphasisRowAllocation allocation;
  final ForumBodyInlineEmphasisPaintReference paintReference;
  final List<ForumBodyParagraphLine> lines;
  final List<List<ForumBodyTextPictureCommand>> _parentCommands;
  double get width => allocation.width;
  double get height => allocation.height;
  TextScaler get textScaler => allocation.input.natural.textScaler;

  ({double top, double height, int coverageStartUtf16, int coverageEndUtf16})
  fragment(int startLine, int endLine) {
    RangeError.checkValidRange(startLine, endLine, lines.length);
    if (startLine == endLine ||
        !lines[startLine].canBreakBefore ||
        !lines[endLine - 1].canBreakAfter) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    final first = lines[startLine], last = lines[endLine - 1];
    return (
      top: first.top,
      height: last.bottom - first.top,
      coverageStartUtf16: first.coverageStartUtf16,
      coverageEndUtf16: last.coverageEndUtf16,
    );
  }

  /// Parent paint only. A consumer must separately bind the original children,
  /// apply the real page clip and admit all current font/scene dependencies.
  /// Native physical strips retain their own transforms and source-free keys.
  ForumBodyTextPictureInput parentPictureInput(int startLine, int endLine) {
    final window = fragment(startLine, endLine);
    final origin = Offset(0, -window.top);
    return ForumBodyTextPictureInput(
      commands: [
        for (var row = startLine; row < endLine; row++)
          for (final command in _parentCommands[row])
            command.translated(origin),
      ],
      maxCommands: ForumBodyTextPictureInput.maximumCommands,
    );
  }
}

/// Current measured resources, transferred exactly once by the preparation.
/// A containing visible transaction may prepare paint and bind children before
/// releasing these fonts. This object itself is not a readable page delivery.
final class ForumBodyInlineFontFrameMeasurement {
  ForumBodyInlineFontFrameMeasurement._(
    this.plan,
    this.natural,
    this.isolated,
    this.paint,
  );
  final ForumBodyInlineFontFramePlan plan;
  final ForumBodyInlineParagraphLease natural, isolated;
  final ForumBodyInlineEmphasisPaintBinding paint;
  bool _closed = false;
  bool get isActive =>
      !_closed &&
      natural.isActive &&
      isolated.isActive &&
      paint.phases.every((p) => p.hasSameActiveOwner(natural));
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases sync* {
    if (!_closed) {
      yield natural;
      yield isolated;
      yield* paint.nativeLeases;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      paint.close();
    } finally {
      try {
        isolated.release();
      } finally {
        natural.release();
      }
    }
  }
}
