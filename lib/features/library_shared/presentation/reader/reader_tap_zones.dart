import 'dart:async';

import 'package:flutter/material.dart';

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
    this.child,
  });

  final VoidCallback onCenterTap;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final double bottomSafeFraction;
  final bool enabled;
  final Widget? child;

  @override
  State<ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<ReaderTapZones> {
  static const double _tapSlop = 18;
  static const Duration _singleTapDelay = Duration(milliseconds: 320);

  int? _activePointer;
  Offset? _downLocalPosition;
  bool _isCandidateCancelled = false;
  bool _suppressCurrentTap = false;
  Timer? _pendingTapTimer;
  Offset? _pendingTapPosition;

  @override
  void dispose() {
    _pendingTapTimer?.cancel();
    _pendingTapPosition = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeFraction = widget.bottomSafeFraction.clamp(0.0, 0.5).toDouble();
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.enabled ? _handlePointerDown : null,
        onPointerMove: widget.enabled ? _handlePointerMove : null,
        onPointerUp: widget.enabled ? _handlePointerUp : null,
        onPointerCancel: widget.enabled ? _handlePointerCancel : null,
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
    if (_activePointer != null) {
      _isCandidateCancelled = true;
      return;
    }
    _activePointer = event.pointer;
    _downLocalPosition = event.localPosition;
    _isCandidateCancelled = !_isInsideActiveTapArea(event.localPosition);

    _suppressCurrentTap = _isDoubleTapCandidate(event.localPosition);
    if (_suppressCurrentTap) {
      _pendingTapTimer?.cancel();
      _pendingTapTimer = null;
      _pendingTapPosition = null;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _isCandidateCancelled) {
      return;
    }
    final down = _downLocalPosition;
    if (down == null || (event.localPosition - down).distance > _tapSlop) {
      _isCandidateCancelled = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    final down = _downLocalPosition;
    final shouldDispatch = !_suppressCurrentTap &&
        !_isCandidateCancelled &&
        down != null &&
        (event.localPosition - down).distance <= _tapSlop;
    final action = shouldDispatch ? _actionForPosition(event.localPosition) : null;
    _resetPointerCandidate();
    if (action == null) {
      _pendingTapPosition = null;
      return;
    }
    _pendingTapTimer?.cancel();
    _pendingTapPosition = event.localPosition;
    _pendingTapTimer = Timer(_singleTapDelay, () {
      _pendingTapPosition = null;
      if (mounted) {
        action();
      }
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) {
      _resetPointerCandidate();
    }
  }

  void _resetPointerCandidate() {
    _activePointer = null;
    _downLocalPosition = null;
    _isCandidateCancelled = false;
    _suppressCurrentTap = false;
  }

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

  bool _isDoubleTapCandidate(Offset position) {
    final pendingPosition = _pendingTapPosition;
    if (!(_pendingTapTimer?.isActive ?? false) || pendingPosition == null) {
      return false;
    }
    if (!_isInsideActiveTapArea(position)) {
      return false;
    }
    return (position - pendingPosition).distance <= 48;
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
