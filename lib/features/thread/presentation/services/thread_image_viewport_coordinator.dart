import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

enum ThreadImageViewportMode { dormant, prefetch, display }

/// Page-scoped scheduler for block images embedded inside a post's column.
///
/// The outer sliver cannot lazily build individual images inside one HTML
/// document, so this coordinator grants work according to each image's actual
/// scroll position instead of the post widget's build time.
final class ThreadImageViewportCoordinator {
  ThreadImageViewportCoordinator({
    this.prefetchExtentFactor = 0.5,
    this.maxVisibleFirstFrames = 2,
    this.maxPrefetchCandidates = 1,
  });

  final double prefetchExtentFactor;
  final int maxVisibleFirstFrames;
  final int maxPrefetchCandidates;
  final Set<ThreadImageViewportHandle> _handles = <ThreadImageViewportHandle>{};
  ScrollPosition? _position;
  bool _evaluationScheduled = false;
  bool _active = true;
  bool _disposed = false;

  @visibleForTesting
  int get registeredImageCount => _handles.length;

  ThreadImageViewportHandle register() {
    final handle = ThreadImageViewportHandle._(this);
    if (!_disposed) {
      _handles.add(handle);
      _scheduleEvaluation();
    }
    return handle;
  }

  void setActive(bool active) {
    if (_disposed || _active == active) {
      return;
    }
    _active = active;
    if (!active) {
      for (final handle in _handles) {
        handle._applyMode(ThreadImageViewportMode.dormant);
      }
      return;
    }
    _scheduleEvaluation();
  }

  void reset() {
    if (_disposed) {
      return;
    }
    for (final handle in _handles) {
      handle._reset();
    }
    _scheduleEvaluation();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _position?.removeListener(_scheduleEvaluation);
    _position = null;
    for (final handle in _handles.toList(growable: false)) {
      handle.dispose();
    }
    _handles.clear();
  }

  void _bind(ThreadImageViewportHandle handle, BuildContext context) {
    if (_disposed || handle._disposed) {
      return;
    }
    handle._context = context;
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scheduleEvaluation);
      _position = position;
      _position?.addListener(_scheduleEvaluation);
    }
    _scheduleEvaluation();
  }

  void _unregister(ThreadImageViewportHandle handle) {
    _handles.remove(handle);
    _scheduleEvaluation();
  }

  void _scheduleEvaluation() {
    if (_disposed || _evaluationScheduled) {
      return;
    }
    _evaluationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluationScheduled = false;
      _evaluate();
    });
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _evaluate() {
    final position = _position;
    if (_disposed || !_active || position == null || !position.hasPixels) {
      return;
    }
    const viewportStart = 0.0;
    final viewportEnd = position.viewportDimension;
    final prefetchExtent = position.viewportDimension * prefetchExtentFactor;
    final placements = <_ThreadImagePlacement>[];
    final placedHandles = <ThreadImageViewportHandle>{};
    for (final handle in _handles) {
      final placement = _placementFor(
        handle,
        viewportStart: viewportStart,
        viewportEnd: viewportEnd,
        prefetchExtent: prefetchExtent,
      );
      if (placement != null) {
        placements.add(placement);
        placedHandles.add(handle);
      }
    }
    for (final handle in _handles) {
      if (!placedHandles.contains(handle)) {
        handle._applyMode(ThreadImageViewportMode.dormant);
      }
    }
    placements.sort((left, right) => left.distance.compareTo(right.distance));

    var waitingVisible = 0;
    for (final placement in placements) {
      final handle = placement.handle;
      var mode = ThreadImageViewportMode.dormant;
      if (placement.visible) {
        if (handle._firstFrameSettled ||
            waitingVisible < maxVisibleFirstFrames) {
          mode = ThreadImageViewportMode.display;
          if (!handle._firstFrameSettled) {
            waitingVisible += 1;
          }
        }
      }
      handle._applyMode(mode);
    }

    // A nearby disk prefetch may use only the capacity left by visible images.
    // This keeps the page-wide cache-miss budget at two while allowing one
    // look-ahead request after the visible first-frame pressure subsides.
    final prefetchLimit = (maxVisibleFirstFrames - waitingVisible).clamp(
      0,
      maxPrefetchCandidates,
    );
    var prefetched = 0;
    for (final placement in placements) {
      if (prefetched >= prefetchLimit) {
        break;
      }
      if (!placement.visible &&
          placement.near &&
          placement.handle.value == ThreadImageViewportMode.dormant) {
        placement.handle._applyMode(ThreadImageViewportMode.prefetch);
        prefetched += 1;
      }
    }
  }

  _ThreadImagePlacement? _placementFor(
    ThreadImageViewportHandle handle, {
    required double viewportStart,
    required double viewportEnd,
    required double prefetchExtent,
  }) {
    final context = handle._context;
    if (handle._disposed || context == null || !context.mounted) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) {
      return null;
    }
    final bounds = MatrixUtils.transformRect(
      renderObject.getTransformTo(viewport),
      renderObject.paintBounds,
    );
    if (!bounds.top.isFinite || !bounds.bottom.isFinite) {
      return null;
    }
    final lower = bounds.top < bounds.bottom ? bounds.top : bounds.bottom;
    final upper = bounds.top < bounds.bottom ? bounds.bottom : bounds.top;
    final visible = upper >= viewportStart && lower <= viewportEnd;
    final near =
        upper >= viewportStart - prefetchExtent &&
        lower <= viewportEnd + prefetchExtent;
    final viewportCenter = (viewportStart + viewportEnd) / 2;
    final imageCenter = (lower + upper) / 2;
    return _ThreadImagePlacement(
      handle: handle,
      visible: visible,
      near: near,
      distance: (imageCenter - viewportCenter).abs(),
    );
  }
}

final class ThreadImageViewportHandle
    extends ValueNotifier<ThreadImageViewportMode> {
  ThreadImageViewportHandle._(this._coordinator)
    : super(ThreadImageViewportMode.dormant);

  final ThreadImageViewportCoordinator _coordinator;
  BuildContext? _context;
  bool _firstFrameSettled = false;
  bool _disposed = false;

  void bind(BuildContext context) {
    _coordinator._bind(this, context);
  }

  void reportFirstFrameSettled() {
    if (_disposed || _firstFrameSettled) {
      return;
    }
    _firstFrameSettled = true;
    _coordinator._scheduleEvaluation();
  }

  void reportLoadStarted() {
    if (_disposed || !_firstFrameSettled) {
      return;
    }
    _firstFrameSettled = false;
    _coordinator._scheduleEvaluation();
  }

  void _applyMode(ThreadImageViewportMode next) {
    if (_disposed || value == next) {
      return;
    }
    if (next != ThreadImageViewportMode.display) {
      _firstFrameSettled = false;
    }
    value = next;
  }

  void _reset() {
    if (_disposed) {
      return;
    }
    _firstFrameSettled = false;
    _applyMode(ThreadImageViewportMode.dormant);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _context = null;
    _coordinator._unregister(this);
    super.dispose();
  }
}

final class _ThreadImagePlacement {
  const _ThreadImagePlacement({
    required this.handle,
    required this.visible,
    required this.near,
    required this.distance,
  });

  final ThreadImageViewportHandle handle;
  final bool visible;
  final bool near;
  final double distance;
}
