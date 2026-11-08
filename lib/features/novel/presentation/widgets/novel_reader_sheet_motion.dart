import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../domain/models/novel_reader_preferences.dart';

/// Wenku8's sheet ownership: the higher-index leaf is the opaque front sheet.
/// Scrubbing backwards removes that same sheet instead of swapping layers at
/// halfway. The PageView rail is cancelled by NovelReaderPageTransition.
class NovelReaderSheetMotion extends SingleChildRenderObjectWidget {
  const NovelReaderSheetMotion({
    super.key,
    required this.controller,
    required this.index,
    required this.effect,
    required this.reverse,
    required super.child,
  });

  final PageController controller;
  final int index;
  final NovelReaderPageEffect effect;
  final bool reverse;
  bool get enabled =>
      effect == NovelReaderPageEffect.fade ||
      effect == NovelReaderPageEffect.cover;

  @override
  NovelReaderSheetMotionRender createRenderObject(BuildContext context) =>
      NovelReaderSheetMotionRender(this);
  @override
  void updateRenderObject(
    BuildContext context,
    NovelReaderSheetMotionRender renderObject,
  ) => renderObject.update(this);
}

class NovelReaderSheetMotionRender extends RenderProxyBox {
  NovelReaderSheetMotionRender(this._config);
  NovelReaderSheetMotion _config;
  final _move = LayerHandle<TransformLayer>();
  final _opacity = LayerHandle<OpacityLayer>();
  PageController? get _clock => _config.enabled ? _config.controller : null;
  double get _offset {
    final controller = _config.controller;
    final page =
        controller.hasClients && controller.position.hasContentDimensions
        ? controller.page ?? controller.initialPage.toDouble()
        : controller.initialPage.toDouble();
    return _config.index - page;
  }

  bool get _visible => !_config.enabled || _offset.abs() < 0.999999;
  Offset get displacement =>
      _config.effect == NovelReaderPageEffect.cover && _offset > 0
      ? Offset(_offset * size.width * (_config.reverse ? -1 : 1), 0)
      : Offset.zero;
  int get alpha => _config.effect == NovelReaderPageEffect.fade
      ? ((1 - _offset).clamp(0.0, 1.0) * 255).round()
      : 255;

  void _tick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(NovelReaderSheetMotion next) {
    final oldClock = _clock;
    _config = next;
    if (attached && oldClock != _clock) {
      oldClock?.removeListener(_tick);
      _clock?.addListener(_tick);
    }
    _tick();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clock?.addListener(_tick);
  }

  @override
  void detach() {
    _clock?.removeListener(_tick);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;
  @override
  Rect get paintBounds => (Offset.zero & size).expandToInclude(
    (Offset.zero & size).shift(displacement),
  );

  void _paintCoverShadow(Canvas canvas, Offset offset) {
    final fraction = _offset;
    if (fraction <= 0 || fraction >= 1) return;
    final envelope = math.sin(math.pi * fraction);
    final width = math.min(22.0, size.width * .055) * envelope;
    if (width < .001) return;
    final fromRight = !_config.reverse;
    final edge = displacement.dx + (fromRight ? 0 : size.width);
    final shadow = Rect.fromLTWH(
      fromRight ? edge - width : edge,
      0,
      width,
      size.height,
    );
    const clear = Color(0x00000000);
    final ink = const Color(0xFF000000).withValues(alpha: .16 * envelope);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    // Only the exposed lower sheet receives this shadow. The front remains
    // opaque and unshaded, including its text and margin.
    canvas.drawRect(
      shadow,
      Paint()
        ..shader = LinearGradient(
          colors: fromRight ? [clear, ink] : [ink, clear],
        ).createShader(shadow),
    );
    canvas.restore();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !_visible || alpha == 0) return;
    if (_config.effect == NovelReaderPageEffect.cover) {
      _opacity.layer = null;
      _paintCoverShadow(context.canvas, offset);
      final delta = displacement;
      if (delta == Offset.zero) {
        _move.layer = null;
        super.paint(context, offset);
      } else {
        _move.layer = context.pushTransform(
          needsCompositing,
          offset,
          Matrix4.translationValues(delta.dx, 0, 0),
          super.paint,
          oldLayer: _move.layer,
        );
      }
    } else {
      _move.layer = null;
      if (alpha == 255) {
        _opacity.layer = null;
        super.paint(context, offset);
      } else {
        _opacity.layer = context.pushOpacity(
          offset,
          alpha,
          super.paint,
          oldLayer: _opacity.layer,
        );
      }
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(displacement.dx, 0, 0, 1);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _visible &&
      alpha > 0 &&
      result.addWithPaintOffset(
        offset: displacement,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_visible && alpha > 0) super.visitChildrenForSemantics(visitor);
  }

  @override
  void dispose() {
    _move.layer = null;
    _opacity.layer = null;
    super.dispose();
  }
}
