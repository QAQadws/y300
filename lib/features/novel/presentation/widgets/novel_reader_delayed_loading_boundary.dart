import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Provides one page-level loading boundary for a reader surface.
///
/// The child remains the only mounted reader surface while it prepares. The
/// opaque layer keeps intermediate layout states out of sight, and the
/// indicator is delayed so fast chapter changes do not flash a spinner.
class NovelReaderDelayedLoadingBoundary extends StatefulWidget {
  const NovelReaderDelayedLoadingBoundary({
    super.key,
    required this.identity,
    required this.isLoading,
    required this.backgroundColor,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
  });

  /// Stable identity of the chapter transition being loaded.
  final Object identity;
  final bool isLoading;
  final Color backgroundColor;
  final Widget child;
  final Duration delay;

  @override
  State<NovelReaderDelayedLoadingBoundary> createState() =>
      _NovelReaderDelayedLoadingBoundaryState();
}

class _NovelReaderDelayedLoadingBoundaryState
    extends State<NovelReaderDelayedLoadingBoundary>
    with TickerProviderStateMixin {
  Ticker? _delayTicker;
  bool _showIndicator = false;

  @override
  void initState() {
    super.initState();
    _syncIndicatorTimer();
  }

  @override
  void didUpdateWidget(covariant NovelReaderDelayedLoadingBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.isLoading != widget.isLoading ||
        oldWidget.delay != widget.delay) {
      _syncIndicatorTimer();
    }
  }

  @override
  void dispose() {
    _delayTicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.isLoading;
    return AbsorbPointer(
      absorbing: isLoading,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (isLoading)
            Positioned.fill(
              child: ColoredBox(
                key: const Key('novel-reader-delayed-loading-surface'),
                color: widget.backgroundColor,
                child: _showIndicator
                    ? const Center(
                        child: SizedBox(
                          key: Key('novel-reader-delayed-loading-indicator'),
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }

  void _syncIndicatorTimer() {
    _delayTicker?.dispose();
    _delayTicker = null;
    _showIndicator = false;

    if (!widget.isLoading) {
      return;
    }
    if (widget.delay <= Duration.zero) {
      _showIndicator = true;
      return;
    }

    final identity = widget.identity;
    _delayTicker = createTicker((elapsed) {
      if (!mounted ||
          !widget.isLoading ||
          widget.identity != identity ||
          _showIndicator) {
        _delayTicker?.stop();
        return;
      }
      if (elapsed < widget.delay) {
        return;
      }
      _delayTicker?.stop();
      setState(() => _showIndicator = true);
    });
    _delayTicker!.start();
  }
}
