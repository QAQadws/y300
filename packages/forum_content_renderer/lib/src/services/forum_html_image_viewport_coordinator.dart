import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';
import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_predecode_host.dart';
import 'forum_html_image_predecode_policy.dart';

enum ForumHtmlImageViewportMode {
  dormant,
  prefetch,
  predecode,
  retained,
  display;

  bool get keepsImageMounted => this == display || this == retained;
}

/// Page-scoped scheduler for block images embedded inside a post's column.
///
/// The outer sliver cannot lazily build individual images inside one HTML
/// document, so this coordinator grants work according to each image's actual
/// scroll position instead of the post widget's build time.
final class ForumHtmlImageViewportCoordinator {
  ForumHtmlImageViewportCoordinator({
    this.prefetchExtentFactor = 0.5,
    this.maxVisibleFirstFrames = 2,
    this.maxPrefetchCandidates = 1,
    this.predecodePolicy,
  });

  final double prefetchExtentFactor;
  final int maxVisibleFirstFrames;
  final int maxPrefetchCandidates;
  final ForumHtmlImagePredecodePolicy? predecodePolicy;
  final Set<ForumHtmlImageViewportWork> _runningWork = {};
  final Set<ForumHtmlImageViewportHandle> _handles =
      <ForumHtmlImageViewportHandle>{};
  ScrollPosition? _position;
  bool _evaluationScheduled = false;
  bool _active = true;
  bool _disposed = false;
  double? _lastPixels;
  bool _towardsBottom = true;

  @visibleForTesting
  int get registeredImageCount => _handles.length;

  ForumHtmlImageViewportHandle register() {
    final handle = ForumHtmlImageViewportHandle._(this);
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
        handle._reset();
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
    _position?.isScrollingNotifier.removeListener(_scheduleEvaluation);
    _position = null;
    for (final handle in _handles.toList(growable: false)) {
      handle.dispose();
    }
    _handles.clear();
    _runningWork.clear();
  }

  void _bind(ForumHtmlImageViewportHandle handle, BuildContext context) {
    if (_disposed || handle._disposed) {
      return;
    }
    handle._context = context;
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scheduleEvaluation);
      _position?.isScrollingNotifier.removeListener(_scheduleEvaluation);
      _position = position;
      _position?.addListener(_scheduleEvaluation);
      _position?.isScrollingNotifier.addListener(_scheduleEvaluation);
      _lastPixels = position?.hasPixels == true ? position!.pixels : null;
    }
    _scheduleEvaluation();
  }

  void _unregister(ForumHtmlImageViewportHandle handle) {
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
    final pixels = position.pixels;
    if (_lastPixels case final double previous when pixels != previous) {
      _towardsBottom =
          (pixels > previous) == (position.axisDirection != AxisDirection.up);
    }
    _lastPixels = pixels;
    final policy = predecodePolicy;
    final prefetchExtent =
        position.viewportDimension *
        (policy == null
            ? prefetchExtentFactor
            : (policy.forwardDiskExtentFactor > policy.backwardDiskExtentFactor
                  ? policy.forwardDiskExtentFactor
                  : policy.backwardDiskExtentFactor));
    final placements = <_ForumHtmlImagePlacement>[];
    final placedHandles = <ForumHtmlImageViewportHandle>{};
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
        handle._setWindow(false);
        handle._applyMode(ForumHtmlImageViewportMode.dormant);
      }
    }
    placements.sort((left, right) => left.distance.compareTo(right.distance));

    var waitingVisible = 0;
    final modes = <ForumHtmlImageViewportHandle, ForumHtmlImageViewportMode>{};
    for (final placement in placements) {
      final handle = placement.handle;
      var mode = ForumHtmlImageViewportMode.dormant;
      if (placement.visible) {
        if (handle._firstFrameSettled ||
            waitingVisible < maxVisibleFirstFrames) {
          mode = ForumHtmlImageViewportMode.display;
          if (!handle._firstFrameSettled) {
            waitingVisible += 1;
          }
        }
      }
      modes[handle] = mode;
    }

    // A nearby disk prefetch may use only the capacity left by visible images.
    // This keeps the page-wide cache-miss budget at two while allowing one
    // look-ahead request after the visible first-frame pressure subsides.
    final prefetchLimit = (maxVisibleFirstFrames - waitingVisible).clamp(
      0,
      maxPrefetchCandidates,
    );
    if (policy != null) {
      _scheduleLookAhead(placements, modes, position, waitingVisible, policy);
    } else {
      var prefetched = 0;
      for (final placement in placements) {
        if (prefetched >= prefetchLimit) break;
        if (!placement.visible &&
            placement.near &&
            modes[placement.handle] == ForumHtmlImageViewportMode.dormant) {
          modes[placement.handle] = ForumHtmlImageViewportMode.prefetch;
          prefetched += 1;
        }
      }
    }
    // Commit once: an unchanged prefetch must not emit dormant/prefetch on
    // every scroll tick and rebuild its image placeholder again.
    for (final entry in modes.entries) {
      entry.key._applyMode(entry.value);
    }
  }

  void _scheduleLookAhead(
    List<_ForumHtmlImagePlacement> placements,
    Map<ForumHtmlImageViewportHandle, ForumHtmlImageViewportMode> modes,
    ScrollPosition position,
    int waitingVisible,
    ForumHtmlImagePredecodePolicy policy,
  ) {
    final ahead =
        placements
            .where((p) => !p.visible && (p.below == _towardsBottom))
            .toList()
          ..sort((a, b) => a.edgeDistance.compareTo(b.edgeDistance));
    final behind =
        placements
            .where((p) => !p.visible && (p.below != _towardsBottom))
            .toList()
          ..sort((a, b) => a.edgeDistance.compareTo(b.edgeDistance));
    final candidates =
        <(ForumHtmlImageViewportHandle, ForumHtmlImageViewportMode)>[];
    // Crossing the visible edge does not retire an admitted frame. Its widget
    // stays mounted while it remains one of the bounded neighboring targets.
    final window = {
      for (final p in placements)
        if (p.visible) p.handle,
    };
    void collect(
      List<_ForumHtmlImagePlacement> items,
      int count,
      double diskFactor,
    ) {
      var decoded = 0;
      for (final p in items) {
        if (p.edgeDistance > position.viewportDimension * diskFactor) continue;
        final handle = p.handle;
        window.add(handle);
        final decode =
            handle._canPredecode &&
            policy.maxDecodedBytesPerImage > 0 &&
            p.edgeDistance <=
                position.viewportDimension * policy.decodeExtentFactor &&
            decoded < count;
        if (decode) decoded++;
        if (decode && handle._decoded) {
          modes[handle] = ForumHtmlImageViewportMode.retained;
          continue;
        }
        candidates.add((
          handle,
          decode
              ? ForumHtmlImageViewportMode.predecode
              : ForumHtmlImageViewportMode.prefetch,
        ));
      }
    }

    collect(ahead, policy.forwardImageCount, policy.forwardDiskExtentFactor);
    collect(behind, policy.backwardImageCount, policy.backwardDiskExtentFactor);
    for (final p in placements) {
      p.handle._setWindow(window.contains(p.handle));
    }
    final ordered = [
      ...candidates.where((c) => c.$2 == ForumHtmlImageViewportMode.predecode),
      ...candidates.where((c) => c.$2 == ForumHtmlImageViewportMode.prefetch),
    ];
    final running = _runningWork.where((w) => w.isActive).firstOrNull;
    if (running != null &&
        candidates.any(
          (c) => c.$1 == running._handle && c.$2 == running.mode,
        )) {
      modes[running._handle] = running.mode;
      return;
    }
    if (_runningWork.isNotEmpty || waitingVisible >= maxVisibleFirstFrames) {
      return;
    }
    for (final (handle, mode) in ordered) {
      if (handle._finished(mode)) continue;
      if (mode == ForumHtmlImageViewportMode.predecode &&
          position.recommendDeferredLoading(handle._context!)) {
        continue;
      }
      modes[handle] = mode;
      break;
    }
  }

  _ForumHtmlImagePlacement? _placementFor(
    ForumHtmlImageViewportHandle handle, {
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
    return _ForumHtmlImagePlacement(
      handle: handle,
      visible: visible,
      near: near,
      distance: (imageCenter - viewportCenter).abs(),
      below: lower > viewportEnd,
      edgeDistance: visible
          ? 0
          : lower > viewportEnd
          ? lower - viewportEnd
          : viewportStart - upper,
    );
  }
}

final class ForumHtmlImageViewportHandle
    extends ValueNotifier<ForumHtmlImageViewportMode> {
  ForumHtmlImageViewportHandle._(this._coordinator)
    : super(ForumHtmlImageViewportMode.dormant);

  final ForumHtmlImageViewportCoordinator _coordinator;
  BuildContext? _context;
  bool _firstFrameSettled = false;
  bool _disposed = false;
  Object? _workIdentity;
  bool _canPredecode = false;
  bool _inWindow = false;
  bool _diskFinished = false;
  bool _decodeFinished = false;
  bool _decoded = false;
  int _generation = 0;
  ForumHtmlImageViewportWork? _work;

  int get maxDecodedBytes =>
      _coordinator.predecodePolicy?.maxDecodedBytesPerImage ?? 0;

  void configureWork({required Object identity, required bool canPredecode}) {
    if (_workIdentity != identity || _canPredecode != canPredecode) {
      _reset();
      _workIdentity = identity;
      _canPredecode = canPredecode;
      _coordinator._scheduleEvaluation();
    }
  }

  ForumHtmlImageViewportWork beginWork() {
    final work = ForumHtmlImageViewportWork._(this, value, _generation);
    _work = work;
    _coordinator._runningWork.add(work);
    return work;
  }

  bool _finished(ForumHtmlImageViewportMode mode) =>
      mode == ForumHtmlImageViewportMode.predecode
      ? _decodeFinished
      : _diskFinished;

  void _setWindow(bool active) {
    if (_inWindow && !active) _clearWork();
    _inWindow = active;
  }

  void _clearWork() {
    _generation++;
    _work?.cancel();
    _diskFinished = false;
    _decodeFinished = false;
    _decoded = false;
  }

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

  void reportFirstFrameRendered({bool? canRetain}) {
    if (_disposed) return;
    final changed = canRetain != null && _decoded != canRetain;
    if (canRetain != null) _decoded = canRetain;
    reportFirstFrameSettled();
    if (changed) _coordinator._scheduleEvaluation();
  }

  void reportImageFailed() {
    if (_disposed) return;
    _decoded = false;
    // A display failure must not become a new automatic look-ahead retry.
    _diskFinished = true;
    _decodeFinished = true;
    reportFirstFrameSettled();
    _coordinator._scheduleEvaluation();
  }

  void reportLoadStarted() {
    if (_disposed) {
      return;
    }
    _decoded = false;
    _firstFrameSettled = false;
    _coordinator._scheduleEvaluation();
  }

  void _applyMode(ForumHtmlImageViewportMode next) {
    if (_disposed || value == next) {
      return;
    }
    if (!next.keepsImageMounted) {
      _firstFrameSettled = false;
    }
    if (_work?.mode != next) _work?.cancel();
    value = next;
  }

  void _reset() {
    if (_disposed) {
      return;
    }
    _firstFrameSettled = false;
    _clearWork();
    _applyMode(ForumHtmlImageViewportMode.dormant);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _clearWork();
    _context = null;
    _coordinator._unregister(this);
    super.dispose();
  }
}

final class _ForumHtmlImagePlacement {
  const _ForumHtmlImagePlacement({
    required this.handle,
    required this.visible,
    required this.near,
    required this.distance,
    required this.below,
    required this.edgeDistance,
  });

  final ForumHtmlImageViewportHandle handle;
  final bool visible;
  final bool near;
  final double distance;
  final bool below;
  final double edgeDistance;
}

/// A single optional-operation lease. Cancellation retires callbacks immediately;
/// capacity is released when the operation actually completes, including I/O.
final class ForumHtmlImageViewportWork implements ForumHtmlImageWorkScope {
  ForumHtmlImageViewportWork._(this._handle, this.mode, this._generation);
  final ForumHtmlImageViewportHandle _handle;
  final ForumHtmlImageViewportMode mode;
  final int _generation;
  bool _cancelled = false;
  bool _completed = false;

  @override
  bool get isActive =>
      !_cancelled &&
      !_completed &&
      !_handle._disposed &&
      _generation == _handle._generation;

  void cancel() => _cancelled = true;

  void complete(ForumHtmlImagePreparationOutcome outcome) {
    if (_completed) return;
    if (isActive && outcome != ForumHtmlImagePreparationOutcome.cancelled) {
      _handle._diskFinished = true;
      _handle._decoded = outcome == ForumHtmlImagePreparationOutcome.decoded;
      if (mode == ForumHtmlImageViewportMode.predecode ||
          outcome == ForumHtmlImagePreparationOutcome.failed) {
        _handle._decodeFinished = true;
      }
    }
    _completed = true;
    _handle._coordinator._runningWork.remove(this);
    _handle._coordinator._scheduleEvaluation();
  }
}
