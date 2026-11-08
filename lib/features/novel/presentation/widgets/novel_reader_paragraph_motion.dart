import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../models/novel_reader_paragraph_clock.dart';

/// Stable renderer hook: changing the selected effect never replaces HTML parts.
Widget decorateNovelReaderParagraph(BuildContext context, Widget child) =>
    _ParagraphTurnPart(child: child);

class NovelReaderParagraphTurnPage extends StatefulWidget {
  const NovelReaderParagraphTurnPage({
    super.key,
    required this.controller,
    required this.index,
    required this.reverse,
    required this.enabled,
    required this.child,
    this.clock,
    this.travelWidth,
  });

  final PageController controller;
  final NovelReaderParagraphClock? clock;
  final double? travelWidth;
  final int index;
  final bool reverse;
  final bool enabled;
  final Widget child;

  @override
  State<NovelReaderParagraphTurnPage> createState() =>
      _NovelReaderParagraphTurnPageState();
}

class _NovelReaderParagraphTurnPageState
    extends State<NovelReaderParagraphTurnPage> {
  late NovelReaderParagraphClock _clock;
  @override
  void initState() {
    super.initState();
    _clock = widget.clock ?? NovelReaderParagraphClock(widget.controller);
  }

  @override
  void didUpdateWidget(NovelReaderParagraphTurnPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock ||
        oldWidget.controller != widget.controller) {
      if (oldWidget.clock == null) _clock.dispose();
      _clock = widget.clock ?? NovelReaderParagraphClock(widget.controller);
    }
  }

  @override
  void dispose() {
    if (widget.clock == null) _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ParagraphTurnScope(
    clock: _clock,
    index: widget.index,
    reverse:
        widget.reverse != (Directionality.of(context) == TextDirection.rtl),
    enabled: widget.enabled,
    travelWidth: widget.travelWidth,
    child: _ParagraphViewport(child: widget.child),
  );
}

class _ParagraphTurnScope extends InheritedWidget {
  const _ParagraphTurnScope({
    required this.clock,
    required this.index,
    required this.reverse,
    required this.enabled,
    required this.travelWidth,
    required super.child,
  });
  final NovelReaderParagraphClock clock;
  final int index;
  final bool reverse, enabled;
  final double? travelWidth;

  @override
  bool updateShouldNotify(_ParagraphTurnScope old) =>
      clock != old.clock ||
      index != old.index ||
      reverse != old.reverse ||
      enabled != old.enabled ||
      travelWidth != old.travelWidth;
}

class _ParagraphViewport extends SingleChildRenderObjectWidget {
  const _ParagraphViewport({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ParagraphViewportRender();
}

class _ParagraphViewportRender extends RenderProxyBox {}

class _ParagraphTurnPart extends StatefulWidget {
  const _ParagraphTurnPart({required this.child});
  final Widget child;

  @override
  State<_ParagraphTurnPart> createState() => _ParagraphTurnPartState();
}

class _ParagraphTurnPartState extends State<_ParagraphTurnPart> {
  final _snapshot = SnapshotController();
  late final _painter = _ParagraphSnapshotPainter(_snapshot);
  @override
  Widget build(BuildContext context) => _ParagraphPaintPart(
    scope: context.dependOnInheritedWidgetOfExactType<_ParagraphTurnScope>(),
    painter: _painter,
    child: SnapshotWidget(
      controller: _snapshot,
      painter: _painter,
      autoresize: true,
      mode: SnapshotMode.permissive,
      child: RepaintBoundary(child: widget.child),
    ),
  );
  @override
  void dispose() {
    _painter.dispose();
    _snapshot.dispose();
    super.dispose();
  }
}

class _ParagraphPaintPart extends SingleChildRenderObjectWidget {
  const _ParagraphPaintPart({
    required this.scope,
    required this.painter,
    required super.child,
  });
  final _ParagraphTurnScope? scope;
  final _ParagraphSnapshotPainter painter;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ParagraphPartRender(scope, painter);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ParagraphPartRender renderObject,
  ) => renderObject.update(scope);
}

/// Only retained paragraph layers move. Geometry comes from actual Flutter
/// layout, so unequal paragraph heights keep the outgoing ink ahead of incoming
/// ink at every shared row. Reversing/cancelling a drag scrubs the same clock.
class _ParagraphPartRender extends RenderProxyBox {
  _ParagraphPartRender(this.scope, this.painter) {
    painter.owner = this;
  }
  _ParagraphTurnScope? scope;
  final _ParagraphSnapshotPainter painter;
  final _translation = LayerHandle<TransformLayer>();
  List<Rect> _paragraphs = const [];
  bool _measuring = false;
  bool get segmented => _paragraphs.length > 1;
  bool get turning =>
      _clock?.turning == true &&
      (scope!.index == _clock!.source || scope!.index == _clock!.target);

  NovelReaderParagraphClock? get _clock =>
      scope?.enabled == true ? scope?.clock : null;

  void _tick() {
    painter.sync();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(_ParagraphTurnScope? next) {
    final oldClock = _clock;
    scope = next;
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
  void performLayout() {
    super.performLayout();
    _measuring = true;
    final paragraphs = <Rect>[];
    void visit(RenderObject object) {
      if (object is RenderForumHtmlParagraphMetrics) {
        final transform = object.getTransformTo(this);
        paragraphs.addAll(
          object.paragraphs.map((r) => MatrixUtils.transformRect(transform, r)),
        );
      } else {
        object.visitChildren(visit);
      }
    }

    if (child != null) visit(child!);
    _measuring = false;
    paragraphs.sort((a, b) => a.top.compareTo(b.top));
    _paragraphs = paragraphs;
    painter.sync();
  }

  Offset _displacement(Rect localBounds) {
    final clock = _clock;
    if (clock == null) return Offset.zero;
    RenderObject? ancestor = parent;
    while (ancestor != null && ancestor is! _ParagraphViewportRender) {
      ancestor = ancestor.parent;
    }
    if (ancestor is! _ParagraphViewportRender || ancestor.size.height <= 0) {
      return Offset.zero;
    }
    final width = scope!.travelWidth ?? ancestor.size.width;
    final sign = scope!.reverse ? -1.0 : 1.0;
    if (!turning) {
      return Offset((scope!.index - clock.page).sign * width * sign, 0);
    }
    final bounds = MatrixUtils.transformRect(
      getTransformTo(ancestor),
      localBounds,
    );
    final outgoing = scope!.index == clock.source;
    final rank = (outgoing ? bounds.top : bounds.bottom) / ancestor.size.height;
    final progress = NovelReaderParagraphMotion.progress(clock.progress, rank);
    final direction = (clock.target > clock.source ? 1.0 : -1.0) * sign;
    return Offset((outgoing ? -progress : 1 - progress) * width * direction, 0);
  }

  Offset get displacement =>
      segmented ? Offset.zero : _displacement(Offset.zero & size);
  @visibleForTesting
  List<Offset> get paragraphDisplacements => [
    for (final bounds in _paragraphs) _displacement(bounds),
  ];

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  Rect get paintBounds => (Offset.zero & size).expandToInclude(
    (Offset.zero & size).shift(displacement),
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    final delta = displacement;
    if (delta == Offset.zero) {
      _translation.layer = null;
      super.paint(context, offset);
      return;
    }
    _translation.layer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(delta.dx, 0, 0),
      super.paint,
      oldLayer: _translation.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_measuring) return;
    final delta = displacement;
    transform.translateByDouble(delta.dx, 0, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: displacement,
        position: position,
        hitTest: (result, position) =>
            super.hitTest(result, position: position),
      );

  @override
  void dispose() {
    painter.owner = null;
    _translation.layer = null;
    super.dispose();
  }
}

/// Only hard-break RichText needs a texture: it cannot be split into separate
/// widgets without changing its shaping and line heights. Reuse that texture
/// throughout the turn; ordinary block paragraphs still move retained layers.
class _ParagraphSnapshotPainter extends SnapshotPainter {
  _ParagraphSnapshotPainter(this.snapshot);
  final SnapshotController snapshot;
  _ParagraphPartRender? owner;
  final _fallback = LayerHandle<TransformLayer>();
  ui.Image? _lastImage;
  @visibleForTesting
  int snapshotCount = 0;

  void sync() {
    snapshot.allowSnapshotting = owner?.segmented == true && owner!.turning;
    if (!snapshot.allowSnapshotting) _lastImage = null;
    notifyListeners();
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    // Non-rasterizable platform views travel as one retained block.
    final delta = owner?.segmented == true
        ? owner!._displacement(Offset.zero & size)
        : Offset.zero;
    if (delta == Offset.zero) {
      _fallback.layer = null;
      painter(context, offset);
    } else {
      _fallback.layer = context.pushTransform(
        true,
        offset,
        Matrix4.translationValues(delta.dx, 0, 0),
        painter,
        oldLayer: _fallback.layer,
      );
    }
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    if (!identical(_lastImage, image)) {
      _lastImage = image;
      snapshotCount++;
    }
    final part = owner;
    if (part == null || !part.segmented || !part.turning) {
      context.canvas.drawImageRect(
        image,
        Offset.zero & sourceSize,
        offset & size,
        Paint(),
      );
      return;
    }
    final paragraphs = part._paragraphs;
    for (var i = 0; i < paragraphs.length; i++) {
      final top = i == 0 ? 0.0 : paragraphs[i].top.clamp(0.0, size.height);
      final bottom = i + 1 == paragraphs.length
          ? size.height
          : paragraphs[i + 1].top.clamp(top, size.height);
      if (bottom <= top) continue;
      // Boundaries come from shaped hard-break paragraphs, not arbitrary
      // screen strips. Blank lines remain with the preceding paragraph.
      final band = Rect.fromLTRB(0, top, size.width, bottom);
      final delta = part._displacement(paragraphs[i]);
      context.canvas.drawImageRect(
        image,
        Rect.fromLTRB(
          0,
          top * pixelRatio,
          sourceSize.width,
          bottom * pixelRatio,
        ),
        band.shift(offset + delta),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParagraphSnapshotPainter oldDelegate) => true;
  @override
  void dispose() {
    owner = null;
    _lastImage = null;
    _fallback.layer = null;
    super.dispose();
  }
}
