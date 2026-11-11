import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../forum_html_inline_background_plan.dart';

/// Paint-only wrapper: RichText retains shaping, selection, links and metrics.
class ForumHtmlInlineBackground extends SingleChildRenderObjectWidget {
  const ForumHtmlInlineBackground({
    super.key,
    required this.plan,
    required super.child,
  });

  final ForumHtmlInlineBackgroundPlan plan;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderForumHtmlInlineBackground(plan);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderForumHtmlInlineBackground renderObject,
  ) {
    renderObject.plan = plan;
  }
}

class RenderForumHtmlInlineBackground extends RenderProxyBox {
  RenderForumHtmlInlineBackground(this._plan);

  ForumHtmlInlineBackgroundPlan _plan;

  set plan(ForumHtmlInlineBackgroundPlan value) {
    if (identical(value, _plan)) return;
    _plan = value;
    markNeedsPaint();
  }

  RenderParagraph? _findParagraph(RenderObject object) {
    if (object is RenderParagraph) {
      return identical(object.text, _plan.text) ? object : null;
    }
    RenderParagraph? result;
    object.visitChildren((child) {
      result ??= _findParagraph(child);
    });
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = child == null ? null : _findParagraph(child!);
    if (paragraph != null) {
      final transform = paragraph.getTransformTo(this);
      final canvas = context.canvas;
      final clipBounds = paragraph.overflow == TextOverflow.visible
          ? null
          : Offset.zero & paragraph.size;
      canvas.save();
      if (clipBounds != null) {
        canvas.clipRect(
          MatrixUtils.transformRect(transform, clipBounds).shift(offset),
        );
      }
      final paint = Paint();
      for (final range in _plan.ranges) {
        // Query the real paragraph at paint time. Alignment can invalidate its
        // text layout without relaying out this proxy; a cached copy drifts.
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        paint.color = range.color;
        for (final rect in _mergeLineBoxes([
          for (final box in boxes) box.toRect(),
        ])) {
          // Centered shrink-wrapped text can select trailing spaces outside
          // its box. Round the visible intersection, not a cap the clip removes.
          final visible = clipBounds == null
              ? rect
              : rect.intersect(clipBounds);
          if (visible.isEmpty) continue;
          final radius = Radius.circular(
            math.min(4, math.min(visible.width, visible.height) / 2),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              MatrixUtils.transformRect(transform, visible).shift(offset),
              radius,
            ),
            paint,
          );
        }
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }
}

/// Join touching style runs on one visual line, retaining gaps in bidi text.
/// No padding is added, so neighboring text and inline widgets stay uncovered.
Iterable<Rect> _mergeLineBoxes(List<Rect> boxes) sync* {
  boxes.removeWhere((box) => box.width <= 0 || box.height <= 0);
  boxes.sort((a, b) => a.top.compareTo(b.top));
  final line = <Rect>[];
  Rect? lineBounds;
  for (final box in boxes) {
    final bounds = lineBounds;
    if (bounds != null && box.top >= bounds.bottom) {
      yield* _mergeTouching(line);
      line.clear();
      lineBounds = null;
    }
    line.add(box);
    lineBounds = lineBounds?.expandToInclude(box) ?? box;
  }
  yield* _mergeTouching(line);
}

Iterable<Rect> _mergeTouching(List<Rect> line) sync* {
  line.sort((a, b) => a.left.compareTo(b.left));
  Rect? pending;
  for (final rect in line) {
    if (pending == null) {
      pending = rect;
    } else if (rect.left <= pending.right + 0.01) {
      pending = pending.expandToInclude(rect);
    } else {
      yield pending;
      pending = rect;
    }
  }
  if (pending != null) yield pending;
}
