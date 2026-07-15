import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_gesture_coordinator.dart';

enum ReaderZoomBehavior { bounded, continuousVertical }

/// Keeps a PageView subtree stable while selectively claiming page swipes.
///
/// The gate itself listens to zoom state. At 1x PageView receives pointer
/// events; while zoomed the foreground absorber keeps them from PageView. The
/// ancestor gesture coordinator still forwards those events to the zoom
/// surface for panning.
class ReaderPagedSwipeGate extends StatefulWidget {
  const ReaderPagedSwipeGate({
    super.key,
    required this.blockedListenable,
    required this.child,
  });

  final ValueListenable<bool> blockedListenable;
  final Widget child;

  @override
  State<ReaderPagedSwipeGate> createState() => _ReaderPagedSwipeGateState();
}

class _ReaderPagedSwipeGateState extends State<ReaderPagedSwipeGate> {
  @override
  void initState() {
    super.initState();
    widget.blockedListenable.addListener(_onBlockedChanged);
  }

  @override
  void didUpdateWidget(ReaderPagedSwipeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockedListenable == widget.blockedListenable) {
      return;
    }
    oldWidget.blockedListenable.removeListener(_onBlockedChanged);
    widget.blockedListenable.addListener(_onBlockedChanged);
  }

  @override
  void dispose() {
    widget.blockedListenable.removeListener(_onBlockedChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.blockedListenable.value;
    return Stack(
      key: const Key('reader-paged-swipe-gate'),
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !blocked,
            child: const AbsorbPointer(child: SizedBox.expand()),
          ),
        ),
      ],
    );
  }

  void _onBlockedChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

/// Backwards-compatible reader zoom wrapper.
///
/// Production readers inject the session [gestureCoordinator] shared with tap
/// zones. Standalone usages get a private coordinator and pointer observer.
class ReaderZoomableImage extends StatefulWidget {
  const ReaderZoomableImage({
    super.key,
    required this.child,
    this.gestureCoordinator,
    this.activePageIndexListenable,
    this.pageIndex,
    this.minScale = 1,
    this.maxScale = 4,
    this.doubleTapScale = 2,
    this.behavior = ReaderZoomBehavior.bounded,
    this.onZoomStateChanged,
  });

  final Widget child;
  final ReaderGestureCoordinator? gestureCoordinator;
  final ValueListenable<int>? activePageIndexListenable;
  final int? pageIndex;
  final double minScale;
  final double maxScale;
  final double doubleTapScale;
  final ReaderZoomBehavior behavior;
  final ValueChanged<bool>? onZoomStateChanged;

  @override
  State<ReaderZoomableImage> createState() => _ReaderZoomableImageState();
}

class _ReaderZoomableImageState extends State<ReaderZoomableImage> {
  late ReaderGestureCoordinator _gestureCoordinator;
  late bool _ownsGestureCoordinator;

  @override
  void initState() {
    super.initState();
    _attachGestureCoordinator();
  }

  @override
  void didUpdateWidget(ReaderZoomableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gestureCoordinator == widget.gestureCoordinator) {
      return;
    }
    if (_ownsGestureCoordinator) {
      _gestureCoordinator.dispose();
    }
    _attachGestureCoordinator();
  }

  @override
  void dispose() {
    if (_ownsGestureCoordinator) {
      _gestureCoordinator.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = ReaderZoomSurface(
      gestureCoordinator: _gestureCoordinator,
      activePageIndexListenable: widget.activePageIndexListenable,
      pageIndex: widget.pageIndex,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      doubleTapScale: widget.doubleTapScale,
      behavior: widget.behavior,
      onZoomStateChanged: widget.onZoomStateChanged,
      child: widget.child,
    );
    if (!_ownsGestureCoordinator) {
      return surface;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) =>
          _gestureCoordinator.handlePointerDown(event, singleTapEnabled: false),
      onPointerMove: _gestureCoordinator.handlePointerMove,
      onPointerUp: (event) =>
          _gestureCoordinator.handlePointerUp(event, singleTapAction: null),
      onPointerCancel: _gestureCoordinator.handlePointerCancel,
      child: surface,
    );
  }

  void _attachGestureCoordinator() {
    _ownsGestureCoordinator = widget.gestureCoordinator == null;
    _gestureCoordinator =
        widget.gestureCoordinator ?? ReaderGestureCoordinator();
  }
}

/// Stable transform surface shared by vertical and paged image readers.
///
/// The transform and image child stay mounted for the lifetime of the page.
/// Raw pointer observation keeps 1x drags in the parent ListView/PageView;
/// paged readers gate their PageView while this surface reports zoomed state.
class ReaderZoomSurface extends StatefulWidget {
  const ReaderZoomSurface({
    super.key,
    required this.gestureCoordinator,
    required this.child,
    this.activePageIndexListenable,
    this.pageIndex,
    this.minScale = 1,
    this.maxScale = 4,
    this.doubleTapScale = 2,
    this.behavior = ReaderZoomBehavior.bounded,
    this.onZoomStateChanged,
  });

  final ReaderGestureCoordinator gestureCoordinator;
  final Widget child;
  final ValueListenable<int>? activePageIndexListenable;
  final int? pageIndex;
  final double minScale;
  final double maxScale;
  final double doubleTapScale;
  final ReaderZoomBehavior behavior;
  final ValueChanged<bool>? onZoomStateChanged;

  @override
  State<ReaderZoomSurface> createState() => _ReaderZoomSurfaceState();
}

class _ReaderZoomSurfaceState extends State<ReaderZoomSurface>
    with SingleTickerProviderStateMixin {
  static const Duration _doubleTapAnimationDuration = Duration(
    milliseconds: 180,
  );
  static const double _minimumPinchDistance = 0.01;
  static const double _restingScaleTolerance = 0.01;

  late final TransformationController _transformationController;
  late final AnimationController _animationController;
  Animation<Matrix4>? _matrixAnimation;
  bool? _animationTargetZoomed;

  final Map<int, Offset> _activePointers = <int, Offset>{};
  bool _rawPinchActive = false;
  List<int> _rawPinchPointerIds = const <int>[];
  double? _rawPinchInitialDistance;
  double? _rawPinchInitialScale;
  Offset? _rawPinchInitialSceneFocalPoint;
  int? _panPointer;
  bool _continuousHorizontalPanActive = false;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController =
        AnimationController(vsync: this, duration: _doubleTapAnimationDuration)
          ..addListener(_onAnimateMatrix)
          ..addStatusListener(_onAnimationStatusChanged);
    _attachExternalListeners();
  }

  @override
  void didUpdateWidget(ReaderZoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gestureCoordinator != widget.gestureCoordinator) {
      oldWidget.gestureCoordinator.removeDoubleTapListener(_onDoubleTap);
      oldWidget.gestureCoordinator.removePointerListener(_onPointerEvent);
      widget.gestureCoordinator.addDoubleTapListener(_onDoubleTap);
      widget.gestureCoordinator.addPointerListener(_onPointerEvent);
    }
    if (oldWidget.activePageIndexListenable !=
        widget.activePageIndexListenable) {
      oldWidget.activePageIndexListenable?.removeListener(_onActivePageChanged);
      widget.activePageIndexListenable?.addListener(_onActivePageChanged);
    }
    _onActivePageChanged();
  }

  @override
  void dispose() {
    widget.gestureCoordinator.removeDoubleTapListener(_onDoubleTap);
    widget.gestureCoordinator.removePointerListener(_onPointerEvent);
    widget.activePageIndexListenable?.removeListener(_onActivePageChanged);
    _transformationController.dispose();
    _animationController
      ..removeListener(_onAnimateMatrix)
      ..removeStatusListener(_onAnimationStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transformKey =
        widget.behavior == ReaderZoomBehavior.continuousVertical
        ? const Key('reader-continuous-zoom-transform')
        : const Key('reader-bounded-zoom-transform');
    return ClipRect(
      child: AnimatedBuilder(
        animation: _transformationController,
        child: widget.child,
        builder: (context, child) => Transform(
          key: transformKey,
          transform: _transformationController.value,
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
    );
  }

  void _attachExternalListeners() {
    widget.gestureCoordinator.addDoubleTapListener(_onDoubleTap);
    widget.gestureCoordinator.addPointerListener(_onPointerEvent);
    widget.activePageIndexListenable?.addListener(_onActivePageChanged);
    _onActivePageChanged();
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _onPointerDown(event);
    } else if (event is PointerMoveEvent) {
      _onPointerMove(event);
    } else if (event is PointerUpEvent) {
      _onPointerUp(event);
    } else if (event is PointerCancelEvent) {
      _onPointerCancel(event);
    }
  }

  void _onActivePageChanged() {
    if (_isCurrentPage) {
      return;
    }
    _resetToRestingState();
  }

  bool get _isCurrentPage {
    final activePageIndex = widget.activePageIndexListenable;
    final pageIndex = widget.pageIndex;
    return activePageIndex == null ||
        pageIndex == null ||
        activePageIndex.value == pageIndex;
  }

  void _onDoubleTap(ReaderDoubleTapDetails details) {
    if (!_isCurrentPage) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final localPosition = renderObject.globalToLocal(details.globalPosition);
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > renderObject.size.width ||
        localPosition.dy > renderObject.size.height) {
      return;
    }

    _stopAnimation();
    if (_currentScale > widget.minScale + _restingScaleTolerance) {
      _animateTo(Matrix4.identity(), targetZoomed: false);
      return;
    }

    final targetScale = widget.doubleTapScale
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    final scenePoint = _transformationController.toScene(localPosition);
    final targetTranslation = _clampTranslation(
      Offset(
        -scenePoint.dx * (targetScale - 1),
        -scenePoint.dy * (targetScale - 1),
      ),
      targetScale,
    );
    final targetMatrix = _matrixFor(targetTranslation, targetScale);
    _setZoomed(true);
    _animateTo(targetMatrix, targetZoomed: true);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_isCurrentPage) {
      return;
    }
    final localPosition = _globalToLocal(event.position);
    final size = context.size;
    if (localPosition == null ||
        size == null ||
        localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > size.width ||
        localPosition.dy > size.height) {
      return;
    }
    _activePointers[event.pointer] = localPosition;
    if (_activePointers.length == 2) {
      _startRawPinch();
      return;
    }
    if (_isZoomed) {
      _panPointer = event.pointer;
      _continuousHorizontalPanActive = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) {
      return;
    }
    final localPosition = _globalToLocal(event.position);
    if (localPosition == null) {
      return;
    }
    _activePointers[event.pointer] = localPosition;
    if (_rawPinchActive) {
      _updateRawPinch();
      return;
    }
    if (_isZoomed && event.pointer == _panPointer) {
      _updatePan(event);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _finishPointer(event.pointer);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishPointer(event.pointer);
  }

  Offset? _globalToLocal(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.globalToLocal(globalPosition);
  }

  void _finishPointer(int pointer) {
    final wasPinchPointer =
        _rawPinchActive && _rawPinchPointerIds.contains(pointer);
    _activePointers.remove(pointer);
    if (wasPinchPointer) {
      _finishRawPinch();
    }
    if (_panPointer == pointer) {
      _panPointer = null;
      _continuousHorizontalPanActive = false;
    }
  }

  void _startRawPinch() {
    final pointerIds = _activePointers.keys.take(2).toList(growable: false);
    final first = _activePointers[pointerIds[0]];
    final second = _activePointers[pointerIds[1]];
    if (first == null || second == null) {
      return;
    }
    final distance = (second - first).distance;
    if (distance <= _minimumPinchDistance) {
      return;
    }

    _stopAnimation();
    final focalPoint = Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
    _rawPinchActive = true;
    _rawPinchPointerIds = pointerIds;
    _rawPinchInitialDistance = distance;
    _rawPinchInitialScale = _currentScale;
    _rawPinchInitialSceneFocalPoint = _transformationController.toScene(
      focalPoint,
    );
    _panPointer = null;
    _setZoomed(true);
  }

  void _updateRawPinch() {
    if (_rawPinchPointerIds.length != 2) {
      return;
    }
    final first = _activePointers[_rawPinchPointerIds[0]];
    final second = _activePointers[_rawPinchPointerIds[1]];
    final initialDistance = _rawPinchInitialDistance;
    final initialScale = _rawPinchInitialScale;
    final sceneFocalPoint = _rawPinchInitialSceneFocalPoint;
    if (first == null ||
        second == null ||
        initialDistance == null ||
        initialScale == null ||
        sceneFocalPoint == null) {
      return;
    }

    final distance = (second - first).distance;
    final scale = (initialScale * distance / initialDistance)
        .clamp(widget.minScale, widget.maxScale)
        .toDouble();
    final focalPoint = Offset(
      (first.dx + second.dx) / 2,
      (first.dy + second.dy) / 2,
    );
    final translation = _clampTranslation(
      focalPoint - sceneFocalPoint * scale,
      scale,
    );
    _transformationController.value = _matrixFor(translation, scale);
    _syncZoomStateFromMatrix();
  }

  void _finishRawPinch() {
    _rawPinchActive = false;
    _rawPinchPointerIds = const <int>[];
    _rawPinchInitialDistance = null;
    _rawPinchInitialScale = null;
    _rawPinchInitialSceneFocalPoint = null;
    _syncZoomStateFromMatrix();
    if (!_isZoomed) {
      _transformationController.value = Matrix4.identity();
    }
  }

  void _updatePan(PointerMoveEvent event) {
    if (widget.behavior == ReaderZoomBehavior.continuousVertical) {
      if (!_continuousHorizontalPanActive) {
        if (event.delta.dx.abs() <= event.delta.dy.abs()) {
          return;
        }
        _continuousHorizontalPanActive = true;
      }
    }
    final matrix = _transformationController.value;
    final translation3 = matrix.getTranslation();
    final verticalDelta =
        widget.behavior == ReaderZoomBehavior.continuousVertical
        ? 0.0
        : event.delta.dy;
    final translation = _clampTranslation(
      Offset(translation3.x + event.delta.dx, translation3.y + verticalDelta),
      _currentScale,
    );
    _transformationController.value = _matrixFor(translation, _currentScale);
  }

  Offset _clampTranslation(Offset translation, double scale) {
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0 || scale <= 1) {
      return Offset.zero;
    }
    final minX = size.width * (1 - scale);
    final minY = size.height * (1 - scale);
    return Offset(
      translation.dx.clamp(minX, 0).toDouble(),
      translation.dy.clamp(minY, 0).toDouble(),
    );
  }

  Matrix4 _matrixFor(Offset translation, double scale) {
    return Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _animateTo(Matrix4 targetMatrix, {required bool targetZoomed}) {
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
    _animationTargetZoomed = targetZoomed;
    _animationController
      ..reset()
      ..forward();
  }

  void _onAnimateMatrix() {
    final animation = _matrixAnimation;
    if (animation == null) {
      return;
    }
    _transformationController.value = animation.value;
    if (_animationTargetZoomed == false) {
      _syncZoomStateFromMatrix();
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    final targetZoomed = _animationTargetZoomed;
    _matrixAnimation = null;
    _animationTargetZoomed = null;
    if (targetZoomed == false) {
      _transformationController.value = Matrix4.identity();
    }
    if (targetZoomed != null) {
      _setZoomed(targetZoomed);
    }
  }

  void _stopAnimation() {
    _animationController.stop();
    _matrixAnimation = null;
    _animationTargetZoomed = null;
  }

  void _syncZoomStateFromMatrix() {
    _setZoomed(_currentScale > widget.minScale + _restingScaleTolerance);
  }

  void _setZoomed(bool value) {
    if (_isZoomed == value) {
      return;
    }
    _isZoomed = value;
    widget.onZoomStateChanged?.call(value);
  }

  void _resetToRestingState() {
    _stopAnimation();
    _activePointers.clear();
    _rawPinchActive = false;
    _rawPinchPointerIds = const <int>[];
    _rawPinchInitialDistance = null;
    _rawPinchInitialScale = null;
    _rawPinchInitialSceneFocalPoint = null;
    _panPointer = null;
    _continuousHorizontalPanActive = false;
    _transformationController.value = Matrix4.identity();
    _setZoomed(false);
  }

  double get _currentScale =>
      _transformationController.value.getMaxScaleOnAxis();
}
