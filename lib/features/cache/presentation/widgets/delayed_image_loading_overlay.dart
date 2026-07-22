import 'dart:async';

import 'package:flutter/material.dart';

/// Adds a non-blocking loading indicator after one uninterrupted load deadline.
///
/// [loadIdentity] isolates timers when a reused image widget starts displaying a
/// different request. [isLoadActive] also checks the owner's live generation so
/// a frame that settles at the deadline cannot flash a stale indicator.
class DelayedImageLoadingOverlay extends StatefulWidget {
  const DelayedImageLoadingOverlay({
    super.key,
    required this.loadIdentity,
    required this.isLoading,
    required this.enabled,
    required this.delay,
    required this.color,
    required this.isLoadActive,
    required this.child,
  });

  final int loadIdentity;
  final bool isLoading;
  final bool enabled;
  final Duration delay;
  final Color? color;
  final bool Function(int loadIdentity) isLoadActive;
  final Widget child;

  @override
  State<DelayedImageLoadingOverlay> createState() =>
      _DelayedImageLoadingOverlayState();
}

class _DelayedImageLoadingOverlayState
    extends State<DelayedImageLoadingOverlay> {
  Timer? _timer;
  bool _showIndicator = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant DelayedImageLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadIdentity != widget.loadIdentity ||
        oldWidget.isLoading != widget.isLoading ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.delay != widget.delay) {
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showIndicator) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Semantics(
                label: '图片加载中',
                child: SizedBox(
                  key: const Key('cached-library-image-loading-indicator'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color:
                        widget.color ??
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    _showIndicator = false;
    if (!widget.enabled || !widget.isLoading) {
      return;
    }
    if (widget.delay.inMicroseconds <= 0) {
      _showIndicator = true;
      return;
    }
    final loadIdentity = widget.loadIdentity;
    _timer = Timer(widget.delay, () {
      if (!mounted ||
          loadIdentity != widget.loadIdentity ||
          !widget.enabled ||
          !widget.isLoading ||
          !widget.isLoadActive(loadIdentity)) {
        return;
      }
      setState(() {
        _showIndicator = true;
      });
    });
  }
}
