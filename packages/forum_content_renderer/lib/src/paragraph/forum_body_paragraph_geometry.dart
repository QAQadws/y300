import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

enum ForumBodyParagraphLayoutFailure {
  width,
  scale,
  indent,
  direction,
  noWrap,
  singleLine,
  coverage,
}

enum ForumBodyParagraphWindow {
  full,
  beforeTerminalEmptyLine,
  terminalEmptyLine,
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
  }) : engineStartUtf16 = engineStartUtf16 ?? startUtf16,
       engineEndUtf16 = engineEndUtf16 ?? endUtf16,
       engineCoverageStartUtf16 =
           engineCoverageStartUtf16 ?? coverageStartUtf16,
       engineCoverageEndUtf16 = engineCoverageEndUtf16 ?? coverageEndUtf16;
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
  final bool canBreakBefore;
  final bool canBreakAfter;
}

bool forumBodyIsDisplayLineBreak(int codeUnit) =>
    codeUnit == 0x0a || codeUnit == 0x2028 || codeUnit == 0x2029;

/// Shared native line extraction. Coordinates come from actual logical engine
/// boundaries, never a visual midpoint, character-count fit or HTML candidate.
List<ForumBodyParagraphLine> forumBodyParagraphLines({
  required TextPainter painter,
  required HtmlDisplayTextProjection display,
  HtmlInlineTextProjection? inline,
  double paintScale = 1,
}) {
  final text = inline?.engineText ?? display.text;
  int displayOffset(int engine) =>
      inline?.displayOffsetAtEngineUtf16(engine) ?? engine;
  bool legal(int engine) =>
      inline?.displayAtEngineUtf16(engine).isExact ??
      (display.sourceAtUtf16(engine).displayUtf16 == engine);
  final metrics = painter.computeLineMetrics();
  final lines = <ForumBodyParagraphLine>[];
  var start = 0;
  for (final metric in metrics) {
    var range = painter.getLineBoundary(TextPosition(offset: start));
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
    var end = range.end;
    if (metric.hardBreak &&
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
