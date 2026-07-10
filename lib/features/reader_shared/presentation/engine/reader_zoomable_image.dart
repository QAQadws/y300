import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum ReaderZoomBehavior { bounded, continuousVertical }

/// Reusable zoomable image container for reader pages.
///
/// Responsibilities:
/// 1. Keep [InteractiveViewer] out of the tree while resting at 1x.
/// 2. Provide double-tap zoom focusing around the tapped local position.
/// 3. Bootstrap direct two-finger zoom without claiming single-finger drags.
/// 4. Provide pinch adjustment and pan after zoom has been activated.
/// 5. Expose a lightweight zoom-state callback so parent widgets can coordinate
///    page/scroll gestures when the image is magnified.
class ReaderZoomableImage extends StatefulWidget {
  const ReaderZoomableImage({
    super.key,
    required this.child,
    this.minScale = 1,
    this.maxScale = 4,
    this.doubleTapScale = 2,
    this.behavior = ReaderZoomBehavior.bounded,
    this.onZoomStateChanged,
  });

  final Widget child;
  final double minScale;
  final double maxScale;
  final double doubleTapScale;
  final ReaderZoomBehavior behavior;
  final ValueChanged<bool>? onZoomStateChanged;

  @override
  State<ReaderZoomableImage> createState() => _ReaderZoomableImageState();
}

class _ReaderZoomableImageState extends State<ReaderZoomableImage>
    with SingleTickerProviderStateMixin {
  static const Duration _doubleTapAnimationDuration = Duration(
    milliseconds: 180,
  );
  static const double _minimumPinchDistance = 0.01;

  late final TransformationController _transformationController;
  late final AnimationController _animationController;

  Animation<Matrix4>? _matrixAnimation;
  Offset? _doubleTapLocalPosition;

  final Map<int, Offset> _activePointers = <int, Offset>{};
  int? _tapCandidatePointer;
  Offset? _tapDownLocalPosition;
  bool _tapCandidateCancelled = false;
  bool _tapCompletesDoubleTap = false;
  Duration? _previousTapUpTime;
  Offset? _previousTapLocalPosition;
  bool _zoomSurfaceActive = false;
  bool _deactivateAfterAnimation = false;
  bool _rawPinchActive = false;
  List<int> _rawPinchPointerIds = const <int>[];
  double? _rawPinchInitialDistance;
  double? _rawPinchInitialScale;
  Offset? _rawPinchInitialSceneFocalPoint;
  bool _continuousHorizontalPanActive = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController =
        AnimationController(vsync: this, duration: _doubleTapAnimationDuration)
          ..addListener(_onAnimateMatrix)
          ..addStatusListener(_onAnimationStatusChanged);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController
      ..removeListener(_onAnimateMatrix)
      ..removeStatusListener(_onAnimationStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.behavior == ReaderZoomBehavior.continuousVertical
        ? ClipRect(
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: _transformationController,
              builder: (context, matrix, child) => Transform(
                key: const Key('reader-continuous-zoom-transform'),
                transform: matrix,
                alignment: Alignment.topLeft,
                child: child,
              ),
              child: widget.child,
            ),
          )
        : _zoomSurfaceActive
        ? InteractiveViewer(
            transformationController: _transformationController,
            minScale: widget.minScale,
            maxScale: widget.maxScale,
            clipBehavior: Clip.hardEdge,
            onInteractionStart: (_) => _animationController.stop(),
            onInteractionEnd: (_) => _deactivateIfRestingAtMinimumScale(),
            child: widget.child,
          )
        : widget.child;

    // Listener 只旁观原始指针事件，不进入手势竞技场。1× 时不构建
    // InteractiveViewer，外层 ListView/PageView 因而独占单指拖动。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: content,
    );
  }

  void _onAnimateMatrix() {
    final animation = _matrixAnimation;
    if (animation == null) {
      return;
    }
    _transformationController.value = animation.value;
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 2 &&
        (!_zoomSurfaceActive ||
            widget.behavior == ReaderZoomBehavior.continuousVertical)) {
      _resetTapCandidate(clearPreviousTap: true);
      _startRawPinch();
      return;
    }

    if (_tapCandidatePointer != null) {
      _resetTapCandidate(clearPreviousTap: true);
      return;
    }

    _tapCandidatePointer = event.pointer;
    _tapDownLocalPosition = event.localPosition;
    _tapCandidateCancelled = false;
    _tapCompletesDoubleTap = _isSecondTap(event);
    _continuousHorizontalPanActive = false;
    if (!_tapCompletesDoubleTap) {
      _clearExpiredPreviousTap(event.timeStamp);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.localPosition;
    }
    if (_rawPinchActive) {
      _updateRawPinch();
      return;
    }
    _updateContinuousHorizontalPan(event);
    if (event.pointer != _tapCandidatePointer || _tapCandidateCancelled) {
      return;
    }
    final down = _tapDownLocalPosition;
    if (down == null || (event.localPosition - down).distance > kTouchSlop) {
      _tapCandidateCancelled = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_rawPinchActive && _rawPinchPointerIds.contains(event.pointer)) {
      _activePointers.remove(event.pointer);
      _finishRawPinch();
      return;
    }
    if (event.pointer == _tapCandidatePointer) {
      _completeTapCandidate(event);
    }
    _activePointers.remove(event.pointer);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_rawPinchActive && _rawPinchPointerIds.contains(event.pointer)) {
      _activePointers.remove(event.pointer);
      _finishRawPinch();
      return;
    }
    if (event.pointer == _tapCandidatePointer) {
      _resetTapCandidate(clearPreviousTap: true);
    }
    _activePointers.remove(event.pointer);
  }

  void _startRawPinch() {
    final pointerIds = _activePointers.keys.take(2).toList(growable: false);
    if (pointerIds.length != 2) {
      return;
    }
    final first = _activePointers[pointerIds[0]];
    final second = _activePointers[pointerIds[1]];
    if (first == null || second == null) {
      return;
    }
    final distance = (second - first).distance;
    if (distance <= _minimumPinchDistance) {
      return;
    }

    _animationController.stop();
    final initialFocalPoint = Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
    _rawPinchActive = true;
    _rawPinchPointerIds = pointerIds;
    _rawPinchInitialDistance = distance;
    _rawPinchInitialScale = _currentScale;
    _rawPinchInitialSceneFocalPoint = _transformationController.toScene(
      initialFocalPoint,
    );
    _activateZoomSurface();
  }

  void _updateRawPinch() {
    if (_rawPinchPointerIds.length != 2) {
      return;
    }
    final first = _activePointers[_rawPinchPointerIds[0]];
    final second = _activePointers[_rawPinchPointerIds[1]];
    final initialDistance = _rawPinchInitialDistance;
    final initialScale = _rawPinchInitialScale;
    final initialSceneFocalPoint = _rawPinchInitialSceneFocalPoint;
    if (first == null ||
        second == null ||
        initialDistance == null ||
        initialScale == null ||
        initialSceneFocalPoint == null) {
      return;
    }

    final currentDistance = (second - first).distance;
    final scale = (initialScale * currentDistance / initialDistance)
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    final currentFocalPoint = Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
    final translation = _clampContinuousTranslation(
      currentFocalPoint - initialSceneFocalPoint * scale,
      scale,
    );
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _updateContinuousHorizontalPan(PointerMoveEvent event) {
    if (widget.behavior != ReaderZoomBehavior.continuousVertical ||
        !_zoomSurfaceActive ||
        event.pointer != _tapCandidatePointer) {
      return;
    }
    final down = _tapDownLocalPosition;
    if (down == null) {
      return;
    }
    final displacement = event.localPosition - down;
    if (!_continuousHorizontalPanActive) {
      if (displacement.dx.abs() <= kTouchSlop ||
          displacement.dx.abs() <= displacement.dy.abs()) {
        return;
      }
      _continuousHorizontalPanActive = true;
      _tapCandidateCancelled = true;
    }
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final currentTranslation = matrix.getTranslation();
    final translation = _clampContinuousTranslation(
      Offset(currentTranslation.x + event.delta.dx, currentTranslation.y),
      scale,
    );
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  Offset _clampContinuousTranslation(Offset translation, double scale) {
    if (widget.behavior != ReaderZoomBehavior.continuousVertical) {
      return translation;
    }
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return translation;
    }
    final minX = size.width * (1 - scale);
    final minY = size.height * (1 - scale);
    return Offset(
      translation.dx.clamp(minX, 0).toDouble(),
      translation.dy.clamp(minY, 0).toDouble(),
    );
  }

  void _finishRawPinch() {
    _rawPinchActive = false;
    _rawPinchPointerIds = const <int>[];
    _rawPinchInitialDistance = null;
    _rawPinchInitialScale = null;
    _rawPinchInitialSceneFocalPoint = null;
    if (_transformationController.value.getMaxScaleOnAxis() <= 1.01) {
      _deactivateZoomSurface();
    }
  }

  bool _isSecondTap(PointerDownEvent event) {
    final previousTime = _previousTapUpTime;
    final previousPosition = _previousTapLocalPosition;
    if (previousTime == null || previousPosition == null) {
      return false;
    }
    final interval = event.timeStamp - previousTime;
    return interval >= Duration.zero &&
        interval <= kDoubleTapTimeout &&
        (event.localPosition - previousPosition).distance <= kDoubleTapSlop;
  }

  void _clearExpiredPreviousTap(Duration currentTime) {
    final previousTime = _previousTapUpTime;
    if (previousTime == null ||
        currentTime - previousTime > kDoubleTapTimeout) {
      _previousTapUpTime = null;
      _previousTapLocalPosition = null;
    }
  }

  void _completeTapCandidate(PointerUpEvent event) {
    final down = _tapDownLocalPosition;
    final isTap =
        !_tapCandidateCancelled &&
        down != null &&
        (event.localPosition - down).distance <= kTouchSlop;
    if (!isTap) {
      _resetTapCandidate(clearPreviousTap: true);
      return;
    }

    if (_tapCompletesDoubleTap) {
      _doubleTapLocalPosition = event.localPosition;
      _resetTapCandidate(clearPreviousTap: true);
      _onDoubleTap();
      return;
    }

    _previousTapUpTime = event.timeStamp;
    _previousTapLocalPosition = event.localPosition;
    _resetTapCandidate(clearPreviousTap: false);
  }

  void _resetTapCandidate({required bool clearPreviousTap}) {
    _tapCandidatePointer = null;
    _tapDownLocalPosition = null;
    _tapCandidateCancelled = false;
    _tapCompletesDoubleTap = false;
    _continuousHorizontalPanActive = false;
    if (clearPreviousTap) {
      _previousTapUpTime = null;
      _previousTapLocalPosition = null;
    }
  }

  void _onDoubleTap() {
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final shouldZoomIn = currentScale <= 1.01;

    if (!shouldZoomIn || _doubleTapLocalPosition == null) {
      _deactivateAfterAnimation = true;
      _animateTo(Matrix4.identity());
      return;
    }

    final targetScale = widget.doubleTapScale
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    final scenePoint = _transformationController.toScene(
      _doubleTapLocalPosition!,
    );

    final targetTranslation = _clampContinuousTranslation(
      Offset(
        -scenePoint.dx * (targetScale - 1),
        -scenePoint.dy * (targetScale - 1),
      ),
      targetScale,
    );
    final targetMatrix = Matrix4.identity()
      ..translateByDouble(targetTranslation.dx, targetTranslation.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, 1, 1);

    _deactivateAfterAnimation = false;
    if (_zoomSurfaceActive) {
      _animateTo(targetMatrix);
      return;
    }
    _activateZoomSurface();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _zoomSurfaceActive) {
        _animateTo(targetMatrix);
      }
    });
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_deactivateAfterAnimation) {
      return;
    }
    _deactivateAfterAnimation = false;
    _deactivateZoomSurface();
  }

  void _deactivateIfRestingAtMinimumScale() {
    if (_transformationController.value.getMaxScaleOnAxis() <= 1.01) {
      _deactivateZoomSurface();
    }
  }

  void _deactivateZoomSurface() {
    if (!_zoomSurfaceActive) {
      return;
    }
    _rawPinchActive = false;
    _rawPinchPointerIds = const <int>[];
    _rawPinchInitialDistance = null;
    _rawPinchInitialScale = null;
    _rawPinchInitialSceneFocalPoint = null;
    _continuousHorizontalPanActive = false;
    _transformationController.value = Matrix4.identity();
    setState(() {
      _zoomSurfaceActive = false;
    });
    widget.onZoomStateChanged?.call(false);
  }

  void _activateZoomSurface() {
    if (_zoomSurfaceActive) {
      return;
    }
    setState(() {
      _zoomSurfaceActive = true;
    });
    widget.onZoomStateChanged?.call(true);
  }

  void _animateTo(Matrix4 targetMatrix) {
    _matrixAnimation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: targetMatrix,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController
      ..stop()
      ..reset()
      ..forward();
  }

  double get _currentScale =>
      _transformationController.value.getMaxScaleOnAxis();
}
