part of 'forum_body_continuous.dart';

sealed class _Paint {
  Rect get bounds;
}

abstract class _CanvasPaint extends _Paint {
  void paint(Canvas canvas);
}

final class _Text implements _CanvasPaint {
  _Text(this.content, this.painter, this.offset, this.scale, this.prefix);
  final ForumBodyParagraphContent content;
  final TextPainter painter;
  Offset offset;
  final double scale;
  final int prefix;
  @override
  Rect get bounds => offset & (painter.size * scale);
  @override
  void paint(Canvas canvas) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }
}

final class _Label implements _CanvasPaint {
  _Label(this.painter, this.offset);
  final TextPainter painter;
  final Offset offset;
  @override
  Rect get bounds => offset & painter.size;
  @override
  void paint(Canvas canvas) => painter.paint(canvas, offset);
}

final class _Rule implements _CanvasPaint {
  _Rule(this.bounds, this.color);
  @override
  final Rect bounds;
  final Color color;
  @override
  void paint(Canvas canvas) => canvas.drawRect(bounds, Paint()..color = color);
}

final class _Background implements _CanvasPaint {
  _Background(this.left, this.width, this.color, this.quote);
  final double left, width;
  final Color? color;
  final ForumBodyQuoteDecoration? quote;
  double? top, bottom;
  @override
  Rect get bounds => Rect.fromLTWH(
    left,
    top ?? 0,
    width,
    math.max(0, (bottom ?? top ?? 0) - (top ?? 0)),
  );
  @override
  void paint(Canvas canvas) {
    final rect = bounds;
    if (rect.isEmpty) return;
    final radius = quote == null
        ? Radius.zero
        : const Radius.circular(ForumBodyQuoteDecoration.radius * 1.0);
    if (color != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = color!,
      );
    }
    if (quote != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top,
          ForumBodyQuoteDecoration.borderWidth * 1.0,
          rect.height,
        ),
        Paint()..color = quote!.borderColor,
      );
    }
  }
}

final class _ContinuousParentData extends ContainerBoxParentData<RenderBox> {
  String path = '';
}

final class _ResourceSlot extends ParentDataWidget<_ContinuousParentData> {
  const _ResourceSlot({super.key, required this.path, required super.child});
  final String path;
  @override
  Type get debugTypicalAncestorWidgetClass => _ContinuousSurface;
  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ContinuousParentData;
    if (data.path == path) return;
    data.path = path;
    renderObject.parent?.markNeedsLayout();
  }
}

final class _Child implements _Paint {
  _Child(this.child);
  final RenderBox child;
  @override
  Rect get bounds =>
      (child.parentData! as _ContinuousParentData).offset & child.size;
}
