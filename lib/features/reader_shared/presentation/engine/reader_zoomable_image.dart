import 'package:flutter/material.dart';

/// Reusable zoomable image container for reader pages.
///
/// Responsibilities:
/// 1. Provide pinch-to-zoom and pan via [InteractiveViewer].
/// 2. Provide double-tap zoom focusing around the tapped local position.
/// 3. Expose a lightweight zoom-state callback so parent widgets can coordinate
///    page/scroll gestures when the image is magnified.
class ReaderZoomableImage extends StatefulWidget {
  const ReaderZoomableImage({
    super.key,
    required this.child,
    this.minScale = 1,
    this.maxScale = 4,
    this.doubleTapScale = 2,
    this.onZoomStateChanged,
  });

  final Widget child;
  final double minScale;
  final double maxScale;
  final double doubleTapScale;
  final ValueChanged<bool>? onZoomStateChanged;

  @override
  State<ReaderZoomableImage> createState() => _ReaderZoomableImageState();
}

class _ReaderZoomableImageState extends State<ReaderZoomableImage>
    with SingleTickerProviderStateMixin {
  static const Duration _doubleTapAnimationDuration = Duration(milliseconds: 180);

  late final TransformationController _transformationController;
  late final AnimationController _animationController;

  Animation<Matrix4>? _matrixAnimation;
  Offset? _doubleTapLocalPosition;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: _doubleTapAnimationDuration,
    )..addListener(_onAnimateMatrix);
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController
      ..removeListener(_onTransformChanged)
      ..dispose();
    _animationController
      ..removeListener(_onAnimateMatrix)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) => _doubleTapLocalPosition = details.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        panEnabled: true,
        scaleEnabled: true,
        clipBehavior: Clip.hardEdge,
        child: widget.child,
      ),
    );
  }

  void _onAnimateMatrix() {
    final animation = _matrixAnimation;
    if (animation == null) {
      return;
    }
    _transformationController.value = animation.value;
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final nextZoomed = scale > 1.01;
    if (nextZoomed == _isZoomed) {
      return;
    }
    _isZoomed = nextZoomed;
    widget.onZoomStateChanged?.call(nextZoomed);
  }

  void _onDoubleTap() {
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final shouldZoomIn = currentScale <= 1.01;

    if (!shouldZoomIn || _doubleTapLocalPosition == null) {
      _animateTo(Matrix4.identity());
      return;
    }

    final targetScale =
        widget.doubleTapScale.clamp(widget.minScale, widget.maxScale).toDouble();
    final scenePoint = _transformationController.toScene(_doubleTapLocalPosition!);

    final targetMatrix = Matrix4.identity()
      ..translateByDouble(
        -scenePoint.dx * (targetScale - 1),
        -scenePoint.dy * (targetScale - 1),
        0,
        1,
      )
      ..scaleByDouble(targetScale, targetScale, 1, 1);

    _animateTo(targetMatrix);
  }

  void _animateTo(Matrix4 targetMatrix) {
    _matrixAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController
      ..stop()
      ..reset()
      ..forward();
  }
}
