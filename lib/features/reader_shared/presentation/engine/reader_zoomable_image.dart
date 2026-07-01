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

  // 只在真正需要时才让 InteractiveViewer 参与手势竞技场。
  //
  // 背景：Flutter 的 InteractiveViewer 只要 panEnabled || scaleEnabled 有一个为
  // true，就会挂载 ScaleGestureRecognizer 进入竞技场。此时即使当前 scale=1×，
  // 单指拖拽也会和外层 ListView/PageView 抢同一次手势。arena 决议是概率性的
  // ——用户会看到"手指在划但内容不动、下一次却又能划"的不跟手表现。
  //
  // 解决：静止 1× 且单指时把两个开关都关掉，InteractiveViewer 就完全不挂手势
  // recognizer，外层滚动独享手势通道。2 指落下（pinch 入场）或已缩放时再开。
  int _activePointerCount = 0;
  bool _shouldClaimGestures = false;

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
    // 外层 Listener 用 translucent 语义：只旁观原始指针事件（pre-arena），不
    // 消费。用它统计当前落下的指针数，从而在 pinch 入场时把 InteractiveViewer
    // 的手势 recognizer 打开。translucent 保证内层 GestureDetector 与
    // InteractiveViewer 仍能正常参加命中测试与竞技场。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) => _doubleTapLocalPosition = details.localPosition,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          // 关键：两个开关同为 false 时，Flutter 框架不挂载内部的
          // GestureDetector，InteractiveViewer 完全退出手势竞技场，外层
          // ListView/PageView 独享滚动手势——彻底解决"1× 静止时不跟手"。
          panEnabled: _shouldClaimGestures,
          scaleEnabled: _shouldClaimGestures,
          clipBehavior: Clip.hardEdge,
          child: widget.child,
        ),
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
    if (nextZoomed != _isZoomed) {
      _isZoomed = nextZoomed;
      widget.onZoomStateChanged?.call(nextZoomed);
    }
    // 缩放状态改变可能导致是否需要独占手势的判定翻转（例如从 1× 双击变缩放
    // 后应重新挂上 pan 手势），单点在此同步。
    _syncGestureClaim();
  }

  void _onPointerDown(PointerDownEvent _) {
    _activePointerCount += 1;
    _syncGestureClaim();
  }

  void _onPointerUp(PointerUpEvent _) {
    _decrementPointer();
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _decrementPointer();
  }

  void _decrementPointer() {
    if (_activePointerCount <= 0) {
      return; // 防御式：不应发生，但即便发生也不能翻负。
    }
    _activePointerCount -= 1;
    _syncGestureClaim();
  }

  /// 只有真正需要参与竞技场时才 setState，避免每次触点抖动都触发 rebuild。
  void _syncGestureClaim() {
    // 判定策略：
    //   - 已缩放（scale > 1×）：pan/scale 都有意义，必须挂上；
    //   - 2 指落下：pinch 入场信号，抢在 arena 决议前打开；
    //   - 其它情况（1× 静止 + ≤1 指）：让外层滚动独享。
    final next = _isZoomed || _activePointerCount >= 2;
    if (next == _shouldClaimGestures) {
      return;
    }
    if (!mounted) {
      _shouldClaimGestures = next;
      return;
    }
    setState(() {
      _shouldClaimGestures = next;
    });
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
