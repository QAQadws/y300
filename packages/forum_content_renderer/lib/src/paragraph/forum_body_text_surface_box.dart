import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:forum_content_renderer/forum_text.dart';

/// Shared lifecycle for prepared native text surfaces. Concrete views supply
/// geometry/paint/source and own their typed leases; this box never acquires.
abstract class ForumBodyTextSurfaceBox extends RenderBox {
  ForumBodyTextSurfaceBox(this._onTap, this._interactionIdentity) {
    _resetTap();
  }
  void Function(HtmlProjectedSourcePosition)? _onTap;
  Object? _interactionIdentity;
  late TapGestureRecognizer _tap;
  bool get isContentActive;
  Size get contentSize;
  HtmlProjectedSourcePosition sourceAt(Offset position);
  void paintContent(Canvas canvas, Offset offset);
  void describeContentSemantics(SemanticsConfiguration config);
  void releaseContent();

  void _resetTap() {
    _tap = TapGestureRecognizer()
      ..onTapUp = (details) {
        if (attached && isContentActive) {
          _onTap?.call(sourceAt(details.localPosition));
        }
      };
  }

  void refreshInteraction({
    required void Function(HtmlProjectedSourcePosition)? onTap,
    required Object? interactionIdentity,
    required bool geometryChanged,
  }) {
    _onTap = onTap;
    if (!geometryChanged && _interactionIdentity == interactionIdentity) return;
    _tap.dispose();
    _resetTap();
    _interactionIdentity = interactionIdentity;
    if (geometryChanged) {
      markNeedsLayout();
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (!isContentActive) return constraints.smallest;
    final content = contentSize;
    final result = constraints.constrain(content);
    if (result.width != content.width || result.height < content.height) {
      throw FlutterError(
        'Paragraph surface constraints do not match its layout',
      );
    }
    return result;
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  double computeMinIntrinsicWidth(double height) => contentSize.width;
  @override
  double computeMaxIntrinsicWidth(double height) => contentSize.width;
  @override
  double computeMinIntrinsicHeight(double width) => contentSize.height;
  @override
  double computeMaxIntrinsicHeight(double width) => contentSize.height;
  @override
  void paint(PaintingContext context, Offset offset) {
    if (isContentActive) paintContent(context.canvas, offset);
  }

  @override
  bool hitTestSelf(Offset position) => _onTap != null && isContentActive;
  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent && _onTap != null && isContentActive) {
      _tap.addPointer(event);
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (isContentActive) describeContentSemantics(config);
  }

  @override
  void detach() {
    _tap.dispose();
    _resetTap();
    super.detach();
  }

  @override
  void dispose() {
    _tap.dispose();
    releaseContent();
    super.dispose();
  }
}
