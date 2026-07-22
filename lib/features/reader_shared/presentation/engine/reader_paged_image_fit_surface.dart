import 'package:flutter/material.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';

enum ReaderPageTurnIntent { previous, next }

/// Applies paged-reader fit geometry independently from image loading.
///
/// Baseline overflow belongs to this surface rather than the zoom transform:
/// width-fit tall images scroll vertically, while height-fit wide images pan
/// horizontally and hand an explicit page-turn intent to the reader at an
/// edge. Neither movement represents reading progress by itself.
class ReaderPagedImageFitSurface extends StatefulWidget {
  const ReaderPagedImageFitSurface({
    super.key,
    required this.ownerId,
    required this.itemId,
    required this.pageIndex,
    required this.pageFit,
    required this.readerMode,
    required this.aspectRatio,
    required this.child,
    required this.onHorizontalOverflowChanged,
    required this.onEdgeTurnRequested,
  }) : assert(pageIndex >= 0),
       assert(aspectRatio > 0);

  static const double edgeTurnThreshold = 48;

  final String ownerId;
  final String itemId;
  final int pageIndex;
  final ReaderPageFitPreference pageFit;
  final ReaderModePreference readerMode;
  final double aspectRatio;
  final Widget child;
  final ValueChanged<bool> onHorizontalOverflowChanged;
  final ValueChanged<ReaderPageTurnIntent> onEdgeTurnRequested;

  @override
  State<ReaderPagedImageFitSurface> createState() =>
      _ReaderPagedImageFitSurfaceState();
}

class _ReaderPagedImageFitSurfaceState
    extends State<ReaderPagedImageFitSurface> {
  static const double _overflowTolerance = 0.5;

  late ScrollController _verticalController;
  late ScrollController _horizontalController;
  bool? _reportedHorizontalOverflow;
  bool _horizontalPositionWasChangedByUser = false;
  bool _leadingEdgeApplied = false;
  bool _edgeTurnRequested = false;
  double _edgeOverscroll = 0;
  int _edgeOverscrollSign = 0;

  @override
  void initState() {
    super.initState();
    _createControllers();
  }

  @override
  void didUpdateWidget(ReaderPagedImageFitSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.itemId != widget.itemId ||
        oldWidget.pageFit != widget.pageFit;
    final directionChanged = oldWidget.readerMode != widget.readerMode;
    if (identityChanged || directionChanged) {
      _resetLocalPosition();
      return;
    }
    if (oldWidget.aspectRatio != widget.aspectRatio &&
        !_horizontalPositionWasChangedByUser) {
      _leadingEdgeApplied = false;
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        if (!viewportWidth.isFinite ||
            !viewportHeight.isFinite ||
            viewportWidth <= 0 ||
            viewportHeight <= 0) {
          _reportHorizontalOverflow(false);
          return widget.child;
        }
        final aspectRatio = _normalizedAspectRatio(widget.aspectRatio);
        switch (widget.pageFit) {
          case ReaderPageFitPreference.fitWidth:
            return _buildWidthFit(
              viewportWidth: viewportWidth,
              viewportHeight: viewportHeight,
              aspectRatio: aspectRatio,
            );
          case ReaderPageFitPreference.fitHeight:
            return _buildHeightFit(
              viewportWidth: viewportWidth,
              viewportHeight: viewportHeight,
              aspectRatio: aspectRatio,
            );
          case ReaderPageFitPreference.contain:
            _reportHorizontalOverflow(false);
            return Center(child: SizedBox.expand(child: widget.child));
        }
      },
    );
  }

  Widget _buildWidthFit({
    required double viewportWidth,
    required double viewportHeight,
    required double aspectRatio,
  }) {
    _reportHorizontalOverflow(false);
    final imageHeight = viewportWidth / aspectRatio;
    final image = SizedBox(
      key: const Key('reader-paged-width-fit-content'),
      width: viewportWidth,
      height: imageHeight,
      child: widget.child,
    );
    if (imageHeight <= viewportHeight + _overflowTolerance) {
      return Center(child: image);
    }
    return SingleChildScrollView(
      key: ValueKey<String>(_scrollIdentity('width')),
      controller: _verticalController,
      primary: false,
      physics: const ClampingScrollPhysics(),
      child: image,
    );
  }

  Widget _buildHeightFit({
    required double viewportWidth,
    required double viewportHeight,
    required double aspectRatio,
  }) {
    final imageWidth = viewportHeight * aspectRatio;
    final image = SizedBox(
      key: const Key('reader-paged-height-fit-content'),
      width: imageWidth,
      height: viewportHeight,
      child: widget.child,
    );
    final hasHorizontalOverflow =
        imageWidth > viewportWidth + _overflowTolerance;
    _reportHorizontalOverflow(hasHorizontalOverflow);
    if (!hasHorizontalOverflow) {
      return Center(child: image);
    }
    _scheduleLeadingEdgeAlignment();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onHorizontalScrollNotification,
        child: SingleChildScrollView(
          key: ValueKey<String>(_scrollIdentity('height')),
          controller: _horizontalController,
          primary: false,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: image,
        ),
      ),
    );
  }

  bool _onHorizontalScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _resetEdgeGesture();
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _horizontalPositionWasChangedByUser = true;
      return false;
    }
    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _horizontalPositionWasChangedByUser = true;
      _accumulateEdgeOverscroll(notification.overscroll);
      return false;
    }
    if (notification is ScrollEndNotification) {
      _resetEdgeGesture();
    }
    return false;
  }

  void _accumulateEdgeOverscroll(double overscroll) {
    if (_edgeTurnRequested || overscroll == 0) {
      return;
    }
    final sign = overscroll.isNegative ? -1 : 1;
    if (_edgeOverscrollSign != sign) {
      _edgeOverscroll = 0;
      _edgeOverscrollSign = sign;
    }
    _edgeOverscroll += overscroll.abs();
    if (_edgeOverscroll < ReaderPagedImageFitSurface.edgeTurnThreshold) {
      return;
    }
    _edgeTurnRequested = true;
    widget.onEdgeTurnRequested(_turnIntentForOverscroll(sign));
  }

  ReaderPageTurnIntent _turnIntentForOverscroll(int sign) {
    final draggedTowardPhysicalLeft = sign > 0;
    final isRtl = widget.readerMode == ReaderModePreference.rtl;
    final isNext = isRtl
        ? !draggedTowardPhysicalLeft
        : draggedTowardPhysicalLeft;
    return isNext ? ReaderPageTurnIntent.next : ReaderPageTurnIntent.previous;
  }

  void _scheduleLeadingEdgeAlignment() {
    if (_leadingEdgeApplied || _horizontalPositionWasChangedByUser) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _leadingEdgeApplied ||
          _horizontalPositionWasChangedByUser ||
          !_horizontalController.hasClients) {
        return;
      }
      final position = _horizontalController.position;
      if (!position.hasContentDimensions) {
        return;
      }
      final target = widget.readerMode == ReaderModePreference.rtl
          ? position.maxScrollExtent
          : position.minScrollExtent;
      _horizontalController.jumpTo(target);
      _leadingEdgeApplied = true;
    });
  }

  void _reportHorizontalOverflow(bool value) {
    if (_reportedHorizontalOverflow == value) {
      return;
    }
    _reportedHorizontalOverflow = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedHorizontalOverflow == value) {
        widget.onHorizontalOverflowChanged(value);
      }
    });
  }

  void _createControllers() {
    _verticalController = ScrollController(keepScrollOffset: false);
    _horizontalController = ScrollController(keepScrollOffset: false);
  }

  void _resetLocalPosition() {
    _reportedHorizontalOverflow = null;
    _horizontalPositionWasChangedByUser = false;
    _leadingEdgeApplied = false;
    _resetEdgeGesture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(
          _verticalController.position.minScrollExtent,
        );
      }
      _scheduleLeadingEdgeAlignment();
    });
  }

  void _resetEdgeGesture() {
    _edgeTurnRequested = false;
    _edgeOverscroll = 0;
    _edgeOverscrollSign = 0;
  }

  double _normalizedAspectRatio(double value) {
    return value.isFinite && value > 0 ? value : 1;
  }

  String _scrollIdentity(String axis) {
    return 'reader-paged-$axis-${widget.ownerId}-${widget.itemId}-'
        '${widget.pageFit.name}';
  }
}
