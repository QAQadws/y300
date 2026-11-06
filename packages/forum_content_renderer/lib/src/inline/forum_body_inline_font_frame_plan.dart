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
    List<int> commandPrefix,
  ) : lines = UnmodifiableListView(lines),
      _parentCommands = UnmodifiableListView(parentCommands),
      _commandPrefix = UnmodifiableListView(commandPrefix);

  static const revision = 4;
  final ForumBodyInlinePlanInput source;
  final ForumBodyInlineEmphasisRowAllocation allocation;
  final ForumBodyInlineEmphasisPaintReference paintReference;
  final List<ForumBodyParagraphLine> lines;
  final List<List<ForumBodyTextPictureCommand>> _parentCommands;
  final List<int> _commandPrefix;
  bool hasParentPaint(int start, int end) {
    fragment(start, end);
    return _commandPrefix[end] > _commandPrefix[start];
  }

  int visibleParentHandleCount(int start, int end) =>
      hasParentPaint(start, end) ? 3 : 2;

  /// Measurement parents plus child-source alias and scene-private aliases.
  /// A child-only window does not record or retain an invented parent picture.
  int preparationParentHandleCount(int start, int end) =>
      hasParentPaint(start, end) ? 10 : 7;
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
    return ForumBodyTextPictureInput(
      commands: parentPictureSteps(
        startLine,
        endLine,
      ).whereType<ForumBodyTextPictureCommand>().toList(growable: false),
      maxCommands: ForumBodyTextPictureInput.maximumCommands,
    );
  }

  /// One row/command per step, including a row whose parent has no ink. Used
  /// by the existing cooperative scene writer without a synchronous full walk.
  Iterable<ForumBodyTextPictureCommand?> parentPictureSteps(
    int startLine,
    int endLine,
  ) sync* {
    final window = fragment(startLine, endLine),
        origin = Offset(0, -window.top);
    for (var row = startLine; row < endLine; row++) {
      final commands = _parentCommands[row];
      if (commands.isEmpty) yield null;
      for (final command in commands) {
        // Virtual native coordinates can be large even on a short visible
        // page. Keep that translation in the qualified row selector rather
        // than manufacturing an out-of-range scene origin.
        yield ForumBodyTextPictureCommand(
          nativeInputIdentity: command.nativeInputIdentity,
          offset: Offset.zero,
          inlineRow: command.inlineRow!.shifted(origin),
        );
      }
    }
  }

  /// At most three already-qualified phase commands. Composition inspects
  /// only new rows, without rebuilding a growing fragment's scene input.
  ForumBodyTextSceneContribution sceneContributionForRow(int row) {
    final metadata = <Object, int>{};
    var inputBytes = 0, pictureBytes = 0, depth = 0;
    final commands = _parentCommands[row];
    for (final command in commands) {
      inputBytes += command.estimatedInputBytes;
      pictureBytes += command.estimatedPictureBytes;
      if (command.translationDepth > depth) depth = command.translationDepth;
      metadata.putIfAbsent(
        command.nativeInputIdentity,
        () => ForumBodyTextPictureInput.estimateRetainedMetadataBytesFor(
          command.nativeInputIdentity,
        ),
      );
    }
    return (
      translationOriginY: null,
      retainedMetadata: Map.unmodifiable(metadata),
      commandCount: commands.length,
      inputCommandBytes: inputBytes,
      pictureCommandBytes: pictureBytes,
      maximumTranslationDepth: depth,
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
