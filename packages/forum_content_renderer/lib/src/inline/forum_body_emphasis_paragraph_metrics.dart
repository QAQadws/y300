import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_paragraph_line_frames.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import '../paragraph/forum_body_paragraph_row_reference.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_emphasis_row_allocation.dart';
import 'forum_body_emphasis_row_input.dart';

part 'forum_body_emphasis_paragraph_preparation.dart';

enum ForumBodyEmphasisParagraphFailure { input, limit, geometry }

final class ForumBodyEmphasisParagraphException implements Exception {
  const ForumBodyEmphasisParagraphException(this.failure);
  final ForumBodyEmphasisParagraphFailure failure;
  @override
  String toString() => 'ForumBodyEmphasisParagraphException(${failure.name})';
}

/// A complete source group placed in its paragraph. Its allocation and source
/// projection remain LOCAL; only these explicit offsets connect them to the
/// original paragraph's display UTF-16 and final physical coordinates.
final class ForumBodyEmphasisParagraphGroup {
  const ForumBodyEmphasisParagraphGroup._(this.sceneInput, this.top);
  final ForumBodyEmphasisAllocatedSceneInput sceneInput;
  ForumBodyEmphasisRowAllocation get allocation => sceneInput.allocation;
  final double top;
  ForumBodyParagraphRowMetrics get source => allocation.source.rowInput!.row;
  int get startLine => source.selector.startLine;
  int get endLine => source.selector.endLine;
  int get startUtf16 => source.startUtf16;
  int get endUtf16 => source.endUtf16;
  double get height => allocation.height;
}

typedef ForumBodyEmphasisParagraphFragment = ({
  int startGroup,
  int endGroup,
  int coverageStartUtf16,
  int coverageEndUtf16,
  double top,
  double height,
});

/// Pure whole-paragraph placement, without a native handle, cache or callback.
/// Source/font qualification belongs to the current visible preparation. Rows
/// inside a complete grapheme never become independent pagination boundaries.
final class ForumBodyEmphasisParagraphMetrics {
  ForumBodyEmphasisParagraphMetrics._({
    required this.glyphInput,
    required this.reference,
    required List<ForumBodyEmphasisParagraphGroup> groups,
    required List<ForumBodyParagraphLine> lines,
    required this.textScaler,
    required this.height,
    required this.alphabeticBaseline,
    required this.hasTerminalEmptyLine,
    required this.markCount,
    required this.retainedTextCodeUnits,
    required this.retainedRuns,
  }) : groups = UnmodifiableListView(groups),
       lines = UnmodifiableListView(lines);
  static const revision = 2;
  final ForumBodyEmphasisGlyphInput glyphInput;
  ForumBodyParagraphContent get content => glyphInput.original;
  final ForumBodyParagraphRowReference reference;
  final List<ForumBodyEmphasisParagraphGroup> groups;
  final List<ForumBodyParagraphLine> lines;
  final TextScaler textScaler;
  Map<double, double> get effectiveScales =>
      (textScaler as _ParagraphScaler).values;
  final double height, alphabeticBaseline;
  final bool hasTerminalEmptyLine;
  final int markCount, retainedTextCodeUnits, retainedRuns;
  double get width => reference.width;

  ({int startLine, int endLine}) lineWindow(ForumBodyParagraphWindow window) {
    if (window == ForumBodyParagraphWindow.full) {
      return (startLine: 0, endLine: lines.length);
    }
    // Captured from the actual native display/engine pair, including indent.
    // Reconstructing engine text from a display projection would lose that proof.
    if (!hasTerminalEmptyLine) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    return window == ForumBodyParagraphWindow.beforeTerminalEmptyLine
        ? (startLine: 0, endLine: lines.length - 1)
        : (startLine: lines.length - 1, endLine: lines.length);
  }

  ForumBodyEmphasisParagraphFragment fragment(int startLine, int endLine) {
    RangeError.checkValidRange(startLine, endLine, lines.length);
    if (startLine == endLine) {
      throw RangeError('A fragment needs a complete source group');
    }
    final start = _groupBoundary(startLine), end = _groupBoundary(endLine);
    final top = groups[start].top, last = groups[end - 1];
    return (
      startGroup: start,
      endGroup: end,
      coverageStartUtf16: groups[start].startUtf16,
      coverageEndUtf16: last.endUtf16,
      top: top,
      height: last.top + last.height - top,
    );
  }

  int _groupBoundary(int line) {
    if (line == lines.length) return groups.length;
    var low = 0, high = groups.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (groups[mid].startLine < line) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low == groups.length || groups[low].startLine != line) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    return low;
  }

  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    int startLine,
    int endLine,
  ) sync* {
    final view = fragment(startLine, endLine);
    for (var index = view.startGroup; index < view.endGroup; index++) {
      yield* groups[index].allocation.nativeFootprint;
    }
  }

  Iterable<ForumBodyTextPictureInput> nativePictureInputsFor(
    int startLine,
    int endLine,
  ) sync* {
    final view = fragment(startLine, endLine);
    for (var index = view.startGroup; index < view.endGroup; index++) {
      yield groups[index].sceneInput.pictureInput;
    }
  }
}
