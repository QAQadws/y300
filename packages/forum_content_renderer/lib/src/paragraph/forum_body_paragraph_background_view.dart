import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_text_background_geometry.dart';
import 'forum_body_paragraph_cache.dart';
import 'forum_body_paragraph_layout.dart';

typedef _BackgroundSpan = ({
  int start,
  int end,
  double? height,
  bool evenLeading,
});

/// Opt-in paint for a mounted window. Source and hit testing still use the
/// original lease. Off-window rectangles of the same author fill keep a page
/// or column cut from becoming an artificial rounded corner.
final class ForumBodyParagraphBackgroundView {
  ForumBodyParagraphBackgroundView._(this._window, this._ink, this._groups);

  final ForumBodyParagraphFragment _window;
  final ForumBodyParagraphLayout _ink;
  final List<({Color color, ForumBodyTextBackgroundGeometry geometry})> _groups;

  static ForumBodyParagraphBackgroundView? prepare(
    ForumBodyParagraphLease lease,
    ForumBodyParagraphFragment window,
  ) {
    final content = lease.content;
    if (!content.hasSolidTextBackground) return null;
    final layout = window.layout;
    final scaler = lease.capturedTextScaler;
    final ranges = <(String?, Color), List<_BackgroundSpan>>{};
    for (final part in content.projection.parts) {
      final style = content.runs[part.runIndex].style;
      final color = forumBodySolidTextBackground(style);
      if (color == null) continue;
      final spans = ranges[(style.textBackgroundPath, color)] ??= [];
      final start = part.utf16Start;
      final end = start + part.text.length;
      final text = style.textStyle;
      final factor = text.height;
      final height = factor != null && factor != kTextHeightNone
          ? scaler.scale(text.fontSize!) * factor * layout.paintScale
          : null;
      final evenLeading =
          text.leadingDistribution == TextLeadingDistribution.even;
      if (spans.isNotEmpty &&
          spans.last.end == start &&
          spans.last.height == height &&
          spans.last.evenLeading == evenLeading) {
        spans.last = (
          start: spans.last.start,
          end: end,
          height: height,
          evenLeading: evenLeading,
        );
      } else {
        spans.add((
          start: start,
          end: end,
          height: height,
          evenLeading: evenLeading,
        ));
      }
    }
    final first = window.startLine == 0 ? 0 : window.startLine - 1;
    final last = window.endLine == layout.lineCount
        ? layout.lineCount - 1
        : window.endLine;
    final start = layout.lines[first].coverageStartUtf16;
    final end = layout.lines[last].coverageEndUtf16;
    final groups =
        <({Color color, ForumBodyTextBackgroundGeometry geometry})>[];
    for (final group in ranges.entries) {
      if (!group.value.any((range) => range.start < end && range.end > start)) {
        continue;
      }
      final rects = [for (final span in group.value) ..._boxes(layout, span)];
      if (rects.isNotEmpty) {
        groups.add((
          color: group.key.$2,
          geometry: ForumBodyTextBackgroundGeometry(rects),
        ));
      }
    }
    if (groups.isEmpty) return null;
    try {
      return ForumBodyParagraphBackgroundView._(
        window,
        lease.prepareTextBackgroundInk(),
        groups,
      );
    } on ForumBodyParagraphBudgetException {
      // Optional paint cannot preempt a visible text layout or its leases.
      return null;
    } on ForumBodyParagraphLayoutException catch (error) {
      if (error.failure != ForumBodyParagraphLayoutFailure.coverage) rethrow;
      return null;
    }
  }

  static Iterable<Rect> _boxes(
    ForumBodyParagraphLayout layout,
    _BackgroundSpan span,
  ) sync* {
    final lines = layout.lines;
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
      for (final box in layout.selectionBoxes(start, end)) {
        final rect = box.toRect();
        if (rect.isEmpty) continue;
        final height = span.height;
        if (height == null) {
          yield rect;
          continue;
        }
        // Tight text boxes exclude the leading used to paint backgrounds.
        // Apply the resolved run height around the actual line baseline.
        final top = span.evenLeading
            ? rect.top - (height - rect.height) / 2
            : line.baseline + (rect.top - line.baseline) * height / rect.height;
        final bottom = top + height;
        yield Rect.fromLTRB(
          rect.left,
          _snapToLineEdge(top, line.top),
          rect.right,
          _snapToLineEdge(bottom, line.bottom),
        );
      }
    }
  }

  static double _snapToLineEdge(double value, double edge) =>
      (value - edge).abs() < .001 ? edge : value;

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
