import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';

/// Tracks only mounted tail rows, using their real viewport geometry. In
/// particular, cache-extent construction is not evidence of visibility.
class ReaderTailActionController extends ChangeNotifier {
  final Set<_TailGeometryBox> _rows = {};
  final Set<ReaderTailActionSurface> _pendingHidden = {};
  Object? _identity;
  ReaderTailActionSurface? _surface;
  bool _vertical = false;
  bool _pagedVisible = false;
  bool _scheduled = false;
  bool _disposed = false;
  bool visible = false;
  double barHeight = 0;

  void configure({
    required Object identity,
    required ReaderTailActionSurface? surface,
    required bool vertical,
    required bool pagedVisible,
  }) {
    if (_identity != identity || !identical(_surface, surface)) {
      final old = _surface;
      if (old != null && visible) _pendingHidden.add(old);
      _identity = identity;
      _surface = surface;
      visible = false;
      barHeight = 0;
    }
    _vertical = vertical;
    _pagedVisible = pagedVisible;
    schedule();
  }

  Object? get identity => _identity;

  void schedule() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      // Deliver the old owner's exit before the new owner's entry, including
      // a mode switch that retains the same business surface instance.
      final hidden = _pendingHidden.toList();
      _pendingHidden.clear();
      for (final surface in hidden) {
        surface.onVisibilityChanged(false);
      }
      final next =
          _surface != null &&
          (_vertical
              ? _rows.any((row) => row.identity == _identity && row.isVisible)
              : _pagedVisible);
      if (next == visible) return;
      visible = next;
      _surface?.onVisibilityChanged(next);
      notifyListeners();
    });
  }

  void measure(double height, Object? identity) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          identity != _identity ||
          (barHeight - height).abs() < 0.5) {
        return;
      }
      barHeight = height;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _rows.clear();
    super.dispose();
  }
}

class ReaderTailVisibilityItem extends SingleChildRenderObjectWidget {
  const ReaderTailVisibilityItem({
    super.key,
    required this.controller,
    required this.identity,
    required super.child,
  });
  final ReaderTailActionController controller;
  final Object? identity;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TailGeometryBox(controller, identity);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final box = renderObject as _TailGeometryBox;
    box.identity = identity;
    box.controller = controller;
    controller.schedule();
  }
}

class _TailGeometryBox extends RenderProxyBox {
  _TailGeometryBox(this.controller, this.identity);
  ReaderTailActionController controller;
  Object? identity;

  bool get isVisible {
    if (!attached || !hasSize || size.isEmpty) return false;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) return false;
    final rect = MatrixUtils.transformRect(
      getTransformTo(viewport),
      Offset.zero & size,
    );
    final intersection = rect.intersect(viewport.paintBounds);
    return intersection.width > 0 && intersection.height > 0;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller._rows.add(this);
    controller.schedule();
  }

  @override
  void detach() {
    controller._rows.remove(this);
    controller.schedule();
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    controller.schedule();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    controller.schedule();
  }
}

class ReaderTailActionOverlay extends StatelessWidget {
  const ReaderTailActionOverlay({
    super.key,
    required this.controller,
    required this.surface,
    required this.menuVisible,
  });
  final ReaderTailActionController controller;
  final ReaderTailActionSurface surface;
  final bool menuVisible;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Offstage(
      offstage: !controller.visible || menuVisible,
      child: TickerMode(
        enabled: controller.visible && !menuVisible,
        child: _ActionBarMeasure(
          onHeight: (height) => controller.measure(height, controller.identity),
          child: surface.buildActionBar(context),
        ),
      ),
    ),
  );
}

class _ActionBarMeasure extends SingleChildRenderObjectWidget {
  const _ActionBarMeasure({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ActionBarMeasureBox(onHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ActionBarMeasureBox renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _ActionBarMeasureBox extends RenderProxyBox {
  _ActionBarMeasureBox(this.onHeight);
  ValueChanged<double> onHeight;
  double? _lastHeight;
  @override
  void performLayout() {
    super.performLayout();
    if (size.height != _lastHeight) {
      _lastHeight = size.height;
      onHeight(size.height);
    }
  }
}
