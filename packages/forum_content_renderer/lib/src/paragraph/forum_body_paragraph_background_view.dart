import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';
import '../style/forum_body_text_background_geometry.dart';
import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_layout.dart';
import 'forum_body_text_layout.dart';

typedef _BackgroundSpan = ({
  int start,
  int end,
  double? height,
  bool evenLeading,
});

typedef ForumBodyTextBackgroundRegion = ({
  String? path,
  Color color,
  List<Rect> rectangles,
});

typedef ForumBodyTextBackgroundRun = ({
  int start,
  int end,
  ForumBodyResolvedStyle style,
});

/// Opt-in paint for a mounted window. Source and hit testing still use the
/// original lease. Off-window rectangles of the same author fill keep a page
/// or column cut from becoming an artificial rounded corner.
final class ForumBodyParagraphBackgroundView {
  ForumBodyParagraphBackgroundView._(this._window, this._ink, this._groups);

  final ForumBodyParagraphFragment _window;
  final ForumBodyTextLayout _ink;
  final List<({Color color, ForumBodyTextBackgroundGeometry geometry})> _groups;

  static ForumBodyParagraphBackgroundView? prepare(
    ForumBodyParagraphLease lease,
    ForumBodyParagraphFragment window,
  ) {
    final layout = window.layout;
    if (!lease.content.hasSolidTextBackground) return null;
    final groups = [
      for (final region in forumBodyLineBackgroundRegions(
        runs: _textRuns(lease.content),
        scaler: lease.capturedTextScaler,
        paintScale: layout.paintScale,
        lines: layout.lines,
        startLine: window.startLine,
        endLine: window.endLine,
        selectionBoxes: layout.selectionBoxes,
      ))
        (
          color: region.color,
          geometry: ForumBodyTextBackgroundGeometry(region.rectangles),
        ),
    ];
    if (groups.isEmpty) return null;
    final ink = forumBodyTryPrepareBackgroundInk(lease);
    return ink == null
        ? null
        : ForumBodyParagraphBackgroundView._(window, ink, groups);
  }

  void paint(
    Canvas canvas,
    Offset offset, {
    Color? color,
    required double radius,
  }) {
    canvas.save();
    try {
      canvas.clipRect(offset & Size(_window.layout.width, _window.height));
      canvas.translate(offset.dx, offset.dy - _window.top);
      final paint = Paint();
      for (final group in _groups) {
        paint.color = color ?? group.color;
        group.geometry.paint(canvas, paint, radius);
      }
      _ink.paint(canvas, Offset.zero);
    } finally {
      canvas.restore();
    }
  }
}

/// Resolve the full natural shape of each author group intersecting this
/// window. Optional row placement maps native strips into the actual flow.
Iterable<ForumBodyTextBackgroundRegion> forumBodyLineBackgroundRegions({
  required Iterable<ForumBodyTextBackgroundRun> runs,
  required TextScaler scaler,
  double paintScale = 1,
  required List<ForumBodyParagraphLine> lines,
  required int startLine,
  required int endLine,
  required List<TextBox> Function(int start, int end) selectionBoxes,
  Offset Function(int line)? placeRow,
}) {
  if (startLine == endLine) return const [];
  final first = math.max(0, startLine - 1);
  final last = math.min(lines.length - 1, endLine);
  return _regions(
    runs,
    scaler,
    lines[first].coverageStartUtf16,
    lines[last].coverageEndUtf16,
    paintScale,
    (span) sync* {
      var low = 0;
      var high = lines.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (lines[middle].coverageEndUtf16 <= span.start) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      for (
        var i = low;
        i < lines.length && lines[i].coverageStartUtf16 < span.end;
        i++
      ) {
        final line = lines[i];
        final start = math.max(span.start, line.startUtf16);
        final end = math.min(span.end, line.unpaintedTrailingSpaceStartUtf16);
        if (start >= end) continue;
        final shift = placeRow?.call(i) ?? Offset.zero;
        for (final box in selectionBoxes(start, end)) {
          final rect = box.toRect();
          if (rect.isEmpty) continue;
          yield _backgroundBox(
            rect,
            span,
            line.baseline,
            line.top,
            line.bottom,
          ).shift(shift);
        }
      }
    },
  );
}

ForumBodyTextLayout? forumBodyTryPrepareBackgroundInk(
  ForumBodyTextLease lease,
) {
  try {
    return lease.prepareTextBackgroundInk();
  } on ForumBodyParagraphBudgetException {
    // Optional paint cannot preempt a visible text layout or its leases.
    return null;
  } on ForumBodyParagraphLayoutException catch (error) {
    if (error.failure != ForumBodyParagraphLayoutFailure.coverage) rethrow;
    return null;
  }
}

Iterable<ForumBodyTextBackgroundRegion> forumBodySingleLineBackgroundRegions(
  ForumBodyTextLease lease,
) {
  final layout = lease.layout;
  final content = lease.content;
  final text = content.projection.text;
  final runs = _textRuns(content);
  final scaler = lease.capturedTextScaler;
  if (layout is ForumBodyParagraphLayout) {
    return forumBodyLineBackgroundRegions(
      runs: runs,
      scaler: scaler,
      paintScale: layout.paintScale,
      lines: layout.lines,
      startLine: 0,
      endLine: layout.lineCount,
      selectionBoxes: layout.selectionBoxes,
    );
  }
  var paintedEnd = text.length;
  while (paintedEnd > 0 && text.codeUnitAt(paintedEnd - 1) == 0x20) {
    paintedEnd--;
  }
  if (paintedEnd == 0) paintedEnd = text.length;
  return _regions(runs, scaler, 0, paintedEnd, 1, (span) sync* {
    final end = math.min(span.end, paintedEnd);
    if (span.start >= end) return;
    for (final box in layout.selectionBoxes(span.start, end)) {
      final rect = box.toRect();
      if (!rect.isEmpty) {
        yield _backgroundBox(
          rect,
          span,
          layout.alphabeticBaseline,
          0,
          layout.height,
        );
      }
    }
  });
}

Iterable<ForumBodyTextBackgroundRun> _textRuns(
  ForumBodyParagraphContent content,
) sync* {
  for (final part in content.projection.parts) {
    yield (
      start: part.utf16Start,
      end: part.utf16Start + part.text.length,
      style: content.runs[part.runIndex].style,
    );
  }
}

Iterable<ForumBodyTextBackgroundRegion> _regions(
  Iterable<ForumBodyTextBackgroundRun> runs,
  TextScaler scaler,
  int start,
  int end,
  double paintScale,
  Iterable<Rect> Function(_BackgroundSpan) boxes,
) sync* {
  final ranges = <(String?, Color), List<_BackgroundSpan>>{};
  for (final run in runs) {
    final style = run.style;
    final color = forumBodySolidTextBackground(style);
    if (color == null) continue;
    final spans = ranges[(style.textBackgroundPath, color)] ??= [];
    final from = run.start;
    final to = run.end;
    final text = style.textStyle;
    final factor = text.height;
    final height = factor != null && factor != kTextHeightNone
        ? scaler.scale(text.fontSize!) * factor * paintScale
        : null;
    final evenLeading =
        text.leadingDistribution == TextLeadingDistribution.even;
    if (spans.isNotEmpty &&
        spans.last.end == from &&
        spans.last.height == height &&
        spans.last.evenLeading == evenLeading) {
      spans.last = (
        start: spans.last.start,
        end: to,
        height: height,
        evenLeading: evenLeading,
      );
    } else {
      spans.add((
        start: from,
        end: to,
        height: height,
        evenLeading: evenLeading,
      ));
    }
  }
  for (final group in ranges.entries) {
    if (!group.value.any((range) => range.start < end && range.end > start)) {
      continue;
    }
    final rects = [for (final span in group.value) ...boxes(span)];
    if (rects.isNotEmpty) {
      yield (path: group.key.$1, color: group.key.$2, rectangles: rects);
    }
  }
}

Rect _backgroundBox(
  Rect rect,
  _BackgroundSpan span,
  double baseline,
  double topEdge,
  double bottomEdge,
) {
  final height = span.height;
  if (height == null) return rect;
  // Tight text boxes exclude the leading used to paint backgrounds.
  final top = span.evenLeading
      ? rect.top - (height - rect.height) / 2
      : baseline + (rect.top - baseline) * height / rect.height;
  return Rect.fromLTRB(
    rect.left,
    _snapToLineEdge(top, topEdge),
    rect.right,
    _snapToLineEdge(top + height, bottomEdge),
  );
}

double _snapToLineEdge(double value, double edge) =>
    (value - edge).abs() < .001 ? edge : value;
