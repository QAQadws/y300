import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tracks the paint layer separately from the Host's decoded-frame callback.
/// A retained composited layer remains valid until its binding is retired.
class ForumHtmlImagePaintObserver extends SingleChildRenderObjectWidget {
  const ForumHtmlImagePaintObserver({
    required this.onPaint,
    required super.child,
    super.key,
  });

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintObserver(onPaint);

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    (renderObject as _PaintObserver).onPaint = onPaint;
  }
}

class _PaintObserver extends RenderProxyBox {
  _PaintObserver(this.onPaint);
  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
