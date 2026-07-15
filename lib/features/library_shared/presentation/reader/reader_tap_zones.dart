import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_gesture_coordinator.dart';

/// Reader tap-zone layout shared by long-form readers.
///
/// This widget listens to raw pointer events as a parent of the reader content.
/// It does not enter Flutter's gesture arena, so scrollable content, PageView
/// swipes, text selection and zoom gestures can keep their native behavior.
class ReaderTapZones extends StatefulWidget {
  const ReaderTapZones({
    super.key,
    required this.onCenterTap,
    this.onLeftTap,
    this.onRightTap,
    this.bottomSafeFraction = 0,
    this.enabled = true,
    this.blockedListenable,
    this.gestureCoordinator,
    this.child,
  });

  final VoidCallback onCenterTap;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final double bottomSafeFraction;
  final bool enabled;
  final ValueListenable<bool>? blockedListenable;
  final ReaderGestureCoordinator? gestureCoordinator;
  final Widget? child;

  @override
  State<ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<ReaderTapZones> {
  late ReaderGestureCoordinator _gestureCoordinator;
  late bool _ownsGestureCoordinator;

  @override
  void initState() {
    super.initState();
    _attachGestureCoordinator();
  }

  @override
  void didUpdateWidget(ReaderTapZones oldWidget) {
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
    final safeFraction = widget.bottomSafeFraction.clamp(0.0, 0.5).toDouble();
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.enabled ? _handlePointerDown : null,
        onPointerMove: widget.enabled
            ? _gestureCoordinator.handlePointerMove
            : null,
        onPointerUp: widget.enabled ? _handlePointerUp : null,
        onPointerCancel: widget.enabled
            ? _gestureCoordinator.handlePointerCancel
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child ?? const SizedBox.expand(),
            IgnorePointer(
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: 1 - safeFraction,
                alignment: Alignment.topCenter,
                child: const Row(
                  children: [
                    Expanded(
                      child: SizedBox.expand(
                        key: Key('shared-reader-left-tap-zone'),
                      ),
                    ),
                    Expanded(
                      child: SizedBox.expand(
                        key: Key('shared-reader-center-tap-zone'),
                      ),
                    ),
                    Expanded(
                      child: SizedBox.expand(
                        key: Key('shared-reader-right-tap-zone'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _gestureCoordinator.handlePointerDown(
      event,
      singleTapEnabled:
          _singleTapEnabled && _isInsideActiveTapArea(event.localPosition),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    final action = _singleTapEnabled
        ? _actionForPosition(event.localPosition)
        : null;
    _gestureCoordinator.handlePointerUp(
      event,
      singleTapAction: action == null
          ? null
          : () {
              if (mounted) {
                action();
              }
            },
    );
  }

  void _attachGestureCoordinator() {
    _ownsGestureCoordinator = widget.gestureCoordinator == null;
    _gestureCoordinator =
        widget.gestureCoordinator ?? ReaderGestureCoordinator();
  }

  bool get _singleTapEnabled =>
      widget.enabled && !(widget.blockedListenable?.value ?? false);

  VoidCallback? _actionForPosition(Offset position) {
    if (!_isInsideActiveTapArea(position)) {
      return null;
    }
    final size = context.size;
    if (size == null || size.width <= 0) {
      return null;
    }
    final zoneWidth = size.width / 3;
    if (position.dx < zoneWidth) {
      return widget.onLeftTap;
    }
    if (position.dx < zoneWidth * 2) {
      return widget.onCenterTap;
    }
    return widget.onRightTap;
  }

  bool _isInsideActiveTapArea(Offset position) {
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return false;
    }
    final safeFraction = widget.bottomSafeFraction.clamp(0.0, 0.5).toDouble();
    final activeHeight = size.height * (1 - safeFraction);
    return position.dx >= 0 &&
        position.dx <= size.width &&
        position.dy >= 0 &&
        position.dy <= activeHeight;
  }
}
