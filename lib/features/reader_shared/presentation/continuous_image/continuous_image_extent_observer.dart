import 'package:flutter/widgets.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

class ContinuousImageExtentObserver extends StatefulWidget {
  const ContinuousImageExtentObserver({
    super.key,
    required this.item,
    required this.aspectRatio,
    required this.dimensionSource,
    required this.onExtentResolved,
    required this.child,
    this.changeThreshold = 0.5,
  });

  final ContinuousImageItem item;
  final double aspectRatio;
  final ContinuousImageDimensionSource dimensionSource;
  final ValueChanged<ContinuousImageExtent> onExtentResolved;
  final Widget child;
  final double changeThreshold;

  @override
  State<ContinuousImageExtentObserver> createState() =>
      _ContinuousImageExtentObserverState();
}

class _ContinuousImageExtentObserverState
    extends State<ContinuousImageExtentObserver> {
  Size? _lastReportedSize;

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant ContinuousImageExtentObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.aspectRatio != widget.aspectRatio ||
        oldWidget.dimensionSource != widget.dimensionSource) {
      _lastReportedSize = null;
    }
    _scheduleReport();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportIfNeeded());
  }

  void _reportIfNeeded() {
    if (!mounted) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    final size = renderBox.size;
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final previous = _lastReportedSize;
    final threshold = widget.changeThreshold;
    if (previous != null &&
        (previous.width - size.width).abs() < threshold &&
        (previous.height - size.height).abs() < threshold) {
      return;
    }
    _lastReportedSize = size;
    widget.onExtentResolved(
      ContinuousImageExtent(
        ownerId: widget.item.ownerId,
        itemId: widget.item.id,
        index: widget.item.index,
        crossAxisExtent: size.width,
        mainAxisExtent: size.height,
        aspectRatio: widget.aspectRatio,
        dimensionSource: widget.dimensionSource,
        measuredAt: DateTime.now(),
      ),
    );
  }
}
