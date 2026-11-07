import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_text.dart';

import 'forum_body_paragraph_painter.dart';

enum ForumBodyParagraphLayoutFailure {
  width,
  scale,
  indent,
  direction,
  noWrap,
  singleLine,
  coverage,
  isolation,
}

enum ForumBodyParagraphWindow {
  full,
  beforeTerminalEmptyLine,
  terminalEmptyLine,
}

/// Native TextBox endpoints are encoded as Float32, while row baselines are
/// returned separately. Bound endpoint/baseline rounding at large isolated
/// coordinates; this is physical validation, never a source-boundary tolerance.
double forumBodyNativeVerticalBoxTolerance(TextBox box, double baseline) {
  final coordinate = math.max(
    baseline.abs(),
    math.max(box.top.abs(), box.bottom.abs()),
  );
  if (!coordinate.isFinite) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.isolation,
    );
  }
  final native = ByteData(4)..setFloat32(0, coordinate);
  final exponent = (native.getUint32(0) >> 23) & 0xff;
  if (exponent == 255) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.isolation,
    );
  }
  final ulp = math.pow(2, exponent == 0 ? -149 : exponent - 150).toDouble();
  return math.max(1e-3, 4 * ulp);
}

/// Compare two actual font frames across a known physical baseline shift.
/// Native Float32 endpoints may round independently; horizontal geometry and
/// source identity remain exact and must be qualified by the caller.
bool forumBodyHaveSameShiftedNativeFontBounds(
  Rect original,
  Rect actual, {
  required double originalBaseline,
  required double actualBaseline,
}) {
  double tolerance(Rect rect, double baseline) =>
      forumBodyNativeVerticalBoxTolerance(
        TextBox.fromLTRBD(
          rect.left,
          rect.top,
          rect.right,
          rect.bottom,
          TextDirection.ltr,
        ),
        baseline,
      );
  final delta = actualBaseline - originalBaseline;
  final vertical =
      tolerance(original, originalBaseline) + tolerance(actual, actualBaseline);
  return actual.left == original.left &&
      actual.right == original.right &&
      (actual.top - original.top - delta).abs() <= vertical &&
      (actual.bottom - original.bottom - delta).abs() <= vertical;
}

/// Source/engine ranges and horizontal layout must survive vertical isolation
/// unchanged. Physical vertical geometry is intentionally checked separately.
bool forumBodyHaveSameParagraphLineInputs(
  ForumBodyParagraphLine a,
  ForumBodyParagraphLine b,
) =>
    a.startUtf16 == b.startUtf16 &&
    a.endUtf16 == b.endUtf16 &&
    a.coverageStartUtf16 == b.coverageStartUtf16 &&
    a.coverageEndUtf16 == b.coverageEndUtf16 &&
    a.engineStartUtf16 == b.engineStartUtf16 &&
    a.engineEndUtf16 == b.engineEndUtf16 &&
    a.engineCoverageStartUtf16 == b.engineCoverageStartUtf16 &&
    a.engineCoverageEndUtf16 == b.engineCoverageEndUtf16 &&
    a.unpaintedTrailingSpaceStartUtf16 == b.unpaintedTrailingSpaceStartUtf16 &&
    a.engineUnpaintedTrailingSpaceStartUtf16 ==
        b.engineUnpaintedTrailingSpaceStartUtf16 &&
    a.canBreakBefore == b.canBreakBefore &&
    a.canBreakAfter == b.canBreakAfter &&
    a.left == b.left &&
    a.width == b.width;

/// Actual vertical output from one native maximum-height selection box.
/// The top may include leading adjustment; it is not a row flow origin.
typedef ForumBodyParagraphMaximumLineFrame = ({double top, double bottom});

/// One actual native glyph query at an explicit display code unit. The engine
/// cluster range may cross physical rows or split a source grapheme at a style
/// seam; it is diagnostic native UTF-16, never a legal source slicing boundary.
final class ForumBodyParagraphGlyphGeometry {
  const ForumBodyParagraphGlyphGeometry({
    required this.lineIndex,
    required this.fontBounds,
    required this.engineClusterRange,
    required this.direction,
  });
  final int lineIndex;
  final Rect fontBounds;
  final TextRange engineClusterRange;
  final TextDirection direction;
}

/// Actual first-line geometry after source policy and width fitting. This is
/// layout output, never a replacement for the reader's stored request.
final class ForumBodyFirstLineIndentGeometry {
  const ForumBodyFirstLineIndentGeometry({
    required this.requestedAdvance,
    required this.appliedAdvance,
    required this.layoutPasses,
  });
  const ForumBodyFirstLineIndentGeometry.none()
    : requestedAdvance = 0,
      appliedAdvance = 0,
      layoutPasses = 1;

  final double requestedAdvance;
  final double appliedAdvance;

  /// Passes used to build this layout; a warm lease does not repeat them.
  final int layoutPasses;
  bool get isReduced => appliedAdvance < requestedAdvance;
}

final class ForumBodyParagraphLayoutException implements Exception {
  const ForumBodyParagraphLayoutException(this.failure);
  final ForumBodyParagraphLayoutFailure failure;
  @override
  String toString() => 'ForumBodyParagraphLayoutException(${failure.name})';
}

/// Actual native row geometry with explicit engine and display coordinates.
/// Paint ranges exclude terminal separators; coverage ranges include them.
/// Only legal boundaries may delimit fragments. Display intervals alone do not
/// prove painted child/source coverage or application semantic identity.
final class ForumBodyParagraphLine {
  const ForumBodyParagraphLine({
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.left,
    required this.width,
    required this.startUtf16,
    required this.endUtf16,
    required this.coverageStartUtf16,
    required this.coverageEndUtf16,
    required this.canBreakBefore,
    required this.canBreakAfter,
    int? engineStartUtf16,
    int? engineEndUtf16,
    int? engineCoverageStartUtf16,
    int? engineCoverageEndUtf16,
    int? unpaintedTrailingSpaceStartUtf16,
    int? engineUnpaintedTrailingSpaceStartUtf16,
  }) : engineStartUtf16 = engineStartUtf16 ?? startUtf16,
       engineEndUtf16 = engineEndUtf16 ?? endUtf16,
       engineCoverageStartUtf16 =
           engineCoverageStartUtf16 ?? coverageStartUtf16,
       engineCoverageEndUtf16 = engineCoverageEndUtf16 ?? coverageEndUtf16,
       unpaintedTrailingSpaceStartUtf16 =
           unpaintedTrailingSpaceStartUtf16 ?? endUtf16,
       engineUnpaintedTrailingSpaceStartUtf16 =
           engineUnpaintedTrailingSpaceStartUtf16 ?? engineEndUtf16 ?? endUtf16;
  final double top;
  final double bottom;
  final double baseline;
  final double left;
  final double width;
  final int startUtf16;
  final int endUtf16;
  final int coverageStartUtf16;
  final int coverageEndUtf16;
  final int engineStartUtf16;
  final int engineEndUtf16;
  final int engineCoverageStartUtf16;
  final int engineCoverageEndUtf16;

  /// Native nonempty rows omit trailing ASCII SPACE from all paint passes.
  /// Selection/coverage coordinates retain those characters. Other whitespace
  /// and all-space rows remain conservative until independently verified.
  final int unpaintedTrailingSpaceStartUtf16;
  final int engineUnpaintedTrailingSpaceStartUtf16;
  final bool canBreakBefore;
  final bool canBreakAfter;

  /// Replace only the physical vertical frame after measured allocation.
  /// All original source/engine ranges and legal break flags remain intact.
  ForumBodyParagraphLine withVerticalFrame({
    required double top,
    required double bottom,
    required double baseline,
  }) => ForumBodyParagraphLine(
    top: top,
    bottom: bottom,
    baseline: baseline,
    left: left,
    width: width,
    startUtf16: startUtf16,
    endUtf16: endUtf16,
    coverageStartUtf16: coverageStartUtf16,
    coverageEndUtf16: coverageEndUtf16,
    engineStartUtf16: engineStartUtf16,
    engineEndUtf16: engineEndUtf16,
    engineCoverageStartUtf16: engineCoverageStartUtf16,
    engineCoverageEndUtf16: engineCoverageEndUtf16,
    unpaintedTrailingSpaceStartUtf16: unpaintedTrailingSpaceStartUtf16,
    engineUnpaintedTrailingSpaceStartUtf16:
        engineUnpaintedTrailingSpaceStartUtf16,
    canBreakBefore: canBreakBefore,
    canBreakAfter: canBreakAfter,
  );

  /// Translate only physical geometry; source/display/engine coordinates and
  /// legal break boundaries keep their original explicit units.
  ForumBodyParagraphLine shift(Offset offset) => ForumBodyParagraphLine(
    top: top + offset.dy,
    bottom: bottom + offset.dy,
    baseline: baseline + offset.dy,
    left: left + offset.dx,
    width: width,
    startUtf16: startUtf16,
    endUtf16: endUtf16,
    coverageStartUtf16: coverageStartUtf16,
    coverageEndUtf16: coverageEndUtf16,
    engineStartUtf16: engineStartUtf16,
    engineEndUtf16: engineEndUtf16,
    engineCoverageStartUtf16: engineCoverageStartUtf16,
    engineCoverageEndUtf16: engineCoverageEndUtf16,
    unpaintedTrailingSpaceStartUtf16: unpaintedTrailingSpaceStartUtf16,
    engineUnpaintedTrailingSpaceStartUtf16:
        engineUnpaintedTrailingSpaceStartUtf16,
    canBreakBefore: canBreakBefore,
    canBreakAfter: canBreakAfter,
  );
}

bool forumBodyIsDisplayLineBreak(int codeUnit) =>
    codeUnit == 0x0a || codeUnit == 0x2028 || codeUnit == 0x2029;

bool forumBodyHasTerminalEmptyLine({
  required List<ForumBodyParagraphLine> lines,
  required String displayText,
  required String engineText,
}) =>
    lines.length >= 2 &&
    displayText.isNotEmpty &&
    engineText.isNotEmpty &&
    forumBodyIsDisplayLineBreak(
      displayText.codeUnitAt(displayText.length - 1),
    ) &&
    forumBodyIsDisplayLineBreak(engineText.codeUnitAt(engineText.length - 1)) &&
    lines.last.width == 0 &&
    lines.last.coverageStartUtf16 == displayText.length &&
    lines.last.coverageEndUtf16 == displayText.length &&
    lines.last.engineCoverageStartUtf16 == engineText.length &&
    lines.last.engineCoverageEndUtf16 == engineText.length;

/// Restricted windows over actual native rows, never a source/HTML slice. Both
/// coordinate axes must prove the terminal empty hard-break row; annotation
/// text hidden behind an atom cannot manufacture a parent terminal separator.
({int startLine, int endLine}) forumBodyParagraphLineWindow({
  required List<ForumBodyParagraphLine> lines,
  required String displayText,
  required String engineText,
  required ForumBodyParagraphWindow window,
}) {
  if (window == ForumBodyParagraphWindow.full) {
    return (startLine: 0, endLine: lines.length);
  }
  if (!forumBodyHasTerminalEmptyLine(
    lines: lines,
    displayText: displayText,
    engineText: engineText,
  )) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.coverage,
    );
  }
  return window == ForumBodyParagraphWindow.beforeTerminalEmptyLine
      ? (startLine: 0, endLine: lines.length - 1)
      : (startLine: lines.length - 1, endLine: lines.length);
}

/// Shared native line extraction. Coordinates come from actual logical engine
/// boundaries, never a visual midpoint, character-count fit or HTML candidate.
List<ForumBodyParagraphLine> forumBodyParagraphLines({
  required TextPainter painter,
  required HtmlDisplayTextProjection display,
  HtmlInlineTextProjection? inline,
  double paintScale = 1,
}) => forumBodyParagraphLinesWithPainter(
  painter: ForumBodyBorrowedTextPainter(painter),
  display: display,
  inline: inline,
  paintScale: paintScale,
);

List<ForumBodyParagraphLine> forumBodyParagraphLinesWithPainter({
  required ForumBodyParagraphPainter painter,
  required HtmlDisplayTextProjection display,
  HtmlInlineTextProjection? inline,
  double paintScale = 1,
}) {
  final text = inline?.engineText ?? display.text;
  int displayOffset(int engine) =>
      inline?.displayOffsetAtEngineUtf16(engine) ?? engine;
  bool legal(int engine) =>
      inline?.isLegalEngineBoundary(engine) ??
      (display.sourceAtUtf16(engine).displayUtf16 == engine);
  final metrics = painter.computeLineMetrics();
  final lines = <ForumBodyParagraphLine>[];
  var start = 0;
  for (final metric in metrics) {
    final boundary = painter.lineBoundaryForRow(metric.lineNumber, start);
    var range = boundary.range;
    if (range.start < 0 || range.end < range.start || range.end > text.length) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    // Some engines return the preceding row for the final empty hard-break
    // line. Only normalize that verified empty row and terminal separators.
    if (metric.lineNumber == metrics.length - 1 &&
        metric.width == 0 &&
        start == text.length &&
        text.isNotEmpty &&
        forumBodyIsDisplayLineBreak(text.codeUnitAt(text.length - 1))) {
      range = TextRange.collapsed(text.length);
    } else if (metric.hardBreak &&
        range.end > range.start &&
        forumBodyIsDisplayLineBreak(text.codeUnitAt(range.end - 1))) {
      range = TextRange(start: range.start, end: range.end - 1);
    }
    var end = boundary.coverageEndUtf16 ?? range.end;
    if (boundary.coverageEndUtf16 == null &&
        metric.hardBreak &&
        end < text.length &&
        forumBodyIsDisplayLineBreak(text.codeUnitAt(end))) {
      end++;
    }
    if (range.start != start ||
        range.end < start ||
        range.end > end ||
        end > text.length) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.coverage,
      );
    }
    var paintedEnd = range.end;
    if (metric.width > 0) {
      while (paintedEnd > range.start &&
          text.codeUnitAt(paintedEnd - 1) == 0x20) {
        paintedEnd--;
      }
    }
    if (paintedEnd < range.end) {
      // A custom font may join SPACE into another glyph. The native API only
      // returns whole glyphs; do not trim across an unverified glyph boundary.
      final firstSpace = painter.getBoxesForSelection(
        TextSelection(baseOffset: paintedEnd, extentOffset: paintedEnd + 1),
      );
      if (firstSpace.isEmpty ||
          firstSpace.any(
            (box) =>
                !box.left.isFinite ||
                !box.right.isFinite ||
                !box.top.isFinite ||
                !box.bottom.isFinite,
          )) {
        paintedEnd = range.end;
      }
    }
    lines.add(
      ForumBodyParagraphLine(
        top: (metric.baseline - metric.ascent) * paintScale,
        bottom: (metric.baseline + metric.descent) * paintScale,
        baseline: metric.baseline * paintScale,
        left: metric.left * paintScale,
        width: metric.width * paintScale,
        startUtf16: displayOffset(range.start),
        endUtf16: displayOffset(range.end),
        coverageStartUtf16: displayOffset(start),
        coverageEndUtf16: displayOffset(end),
        engineStartUtf16: range.start,
        engineEndUtf16: range.end,
        engineCoverageStartUtf16: start,
        engineCoverageEndUtf16: end,
        unpaintedTrailingSpaceStartUtf16: displayOffset(paintedEnd),
        engineUnpaintedTrailingSpaceStartUtf16: paintedEnd,
        canBreakBefore: legal(start),
        canBreakAfter: legal(end),
      ),
    );
    start = end;
  }
  if (start != text.length) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.coverage,
    );
  }
  return List.unmodifiable(lines);
}

/// Exclude only the native row's verified omitted SPACE suffix. Keeping the
/// original range across every other boundary preserves breaks and glyphs;
/// no caller may use the omitted interval itself as painted-source evidence.
Iterable<TextRange> forumBodyPaintedTextRanges(
  List<ForumBodyParagraphLine> lines,
  int start,
  int end,
) sync* {
  if (start >= end) return;
  var low = 0, high = lines.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (lines[middle].coverageEndUtf16 <= start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  var cursor = start;
  for (
    var i = low;
    i < lines.length && lines[i].coverageStartUtf16 < end;
    i++
  ) {
    final line = lines[i];
    final omittedStart = line.unpaintedTrailingSpaceStartUtf16.clamp(
      cursor,
      end,
    );
    final omittedEnd = line.endUtf16.clamp(cursor, end);
    if (omittedStart >= omittedEnd) continue;
    if (cursor < omittedStart) {
      yield TextRange(start: cursor, end: omittedStart);
    }
    cursor = omittedEnd;
  }
  if (cursor < end) {
    yield TextRange(start: cursor, end: end);
  }
}
