import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final class ThreadPostViewportAnchorSnapshot {
  const ThreadPostViewportAnchorSnapshot({
    required this.pid,
    required this.relativeTop,
    required this.scrollPixels,
    required this.wasAtLeadingEdge,
    this.chunkStartUnit,
    this.navigationRevision = 0,
  });

  final String? pid;
  final double relativeTop;
  final double scrollPixels;
  final bool wasAtLeadingEdge;
  final int? chunkStartUnit;
  final int navigationRevision;
}

/// Keeps the first visible post stable while a page-level text projection
/// changes post heights.
///
/// This coordinator is deliberately separate from the image layout stabilizer:
/// a projection swaps the whole page in one frame, while an image shift is an
/// incremental resource-layout event.
final class ThreadPostViewportAnchorCoordinator {
  ThreadPostViewportAnchorCoordinator({
    required ScrollController? scrollController,
    required GlobalKey viewportKey,
  }) : _scrollController = scrollController,
       _viewportKey = viewportKey {
    scrollController?.addListener(_onScroll);
  }

  ScrollController? _scrollController;
  final GlobalKey _viewportKey;
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  final Map<String, Map<int, GlobalKey>> _chunkKeys = {};
  final Map<String, Map<int, int>> _chunkEnds = {};
  int _restoreGeneration = 0;
  int _navigationRevision = 0;
  double? _lastPixels;
  bool _performingRestore = false;
  bool _disposed = false;
  static const double _pixelTolerance = 0.5;

  GlobalKey keyForPid(String pid) {
    final normalized = pid.trim();
    return _postKeys.putIfAbsent(
      normalized,
      () => GlobalKey(debugLabel: 'thread-post-anchor-$normalized'),
    );
  }

  void beginExplicitNavigation() {
    _navigationRevision++;
    _restoreGeneration++;
  }

  /// Display units are stable hard-line/paragraph boundaries, not saved anchors.
  GlobalKey keyForChunk(String pid, int startUnit, {required int endUnit}) {
    final normalized = pid.trim();
    (_chunkEnds[normalized] ??= {})[startUnit] = endUnit;
    return (_chunkKeys[normalized] ??= {}).putIfAbsent(
      startUnit,
      () => GlobalKey(debugLabel: 'thread-chunk-anchor-$pid-$startUnit'),
    );
  }

  void updateScrollController(ScrollController? scrollController) {
    _scrollController?.removeListener(_onScroll);
    if (!identical(_scrollController, scrollController)) _navigationRevision++;
    _scrollController = scrollController;
    scrollController?.addListener(_onScroll);
    _lastPixels = scrollController?.hasClients == true
        ? scrollController!.position.pixels
        : null;
    _restoreGeneration += 1;
  }

  void prune(Iterable<String> activePids) {
    final active = activePids.map((pid) => pid.trim()).toSet();
    _postKeys.removeWhere((pid, _) => !active.contains(pid));
    _chunkKeys.removeWhere((pid, _) => !active.contains(pid));
    _chunkEnds.removeWhere((pid, _) => !active.contains(pid));
  }

  ThreadPostViewportAnchorSnapshot? capture(Iterable<String> orderedPids) {
    final controller = _scrollController;
    if (_disposed ||
        controller == null ||
        !controller.hasClients ||
        _isUserScrolling(controller.position)) {
      return null;
    }
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return null;
    }

    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    String? firstVisiblePid;
    var firstVisibleTop = double.infinity;
    int? firstVisibleChunk;

    for (final rawPid in orderedPids) {
      final pid = rawPid.trim();
      final candidates = <(GlobalKey?, int?)>[
        (_postKeys[pid], null),
        for (final entry
            in _chunkKeys[pid]?.entries ?? <MapEntry<int, GlobalKey>>[])
          (entry.value, entry.key),
      ];
      double? pidVisibleTop;
      int? pidVisibleChunk;
      var pidBoundaryVisible = false;
      for (final candidate in candidates) {
        final renderObject = candidate.$1?.currentContext?.findRenderObject();
        if (renderObject is! RenderBox ||
            !renderObject.attached ||
            !renderObject.hasSize) {
          continue;
        }
        final top = renderObject.localToGlobal(Offset.zero).dy;
        final bottom = top + renderObject.size.height;
        if (bottom <= viewportTop || top >= viewportBottom) {
          continue;
        }
        final boundaryVisible = candidate.$2 != null && top >= viewportTop;
        // Prefer a visible block start over the clipped preceding block. Its
        // stable display unit remains meaningful when that predecessor grows.
        if (pidVisibleTop == null ||
            boundaryVisible && !pidBoundaryVisible ||
            boundaryVisible == pidBoundaryVisible && top < pidVisibleTop) {
          pidVisibleTop = top;
          pidVisibleChunk = candidate.$2;
          pidBoundaryVisible = boundaryVisible;
        }
      }
      if (pidVisibleTop != null && pidVisibleTop < firstVisibleTop) {
        firstVisibleTop = pidVisibleTop;
        firstVisiblePid = pid;
        firstVisibleChunk = pidVisibleChunk;
      }
    }

    final position = controller.position;
    _lastPixels = position.pixels;
    return ThreadPostViewportAnchorSnapshot(
      pid: firstVisiblePid,
      relativeTop: firstVisiblePid == null ? 0 : firstVisibleTop - viewportTop,
      scrollPixels: position.pixels,
      wasAtLeadingEdge:
          position.pixels <= position.minScrollExtent + _pixelTolerance,
      chunkStartUnit: firstVisibleChunk,
      navigationRevision: _navigationRevision,
    );
  }

  void restoreAfterFrame(ThreadPostViewportAnchorSnapshot? snapshot) {
    if (snapshot == null ||
        _disposed ||
        snapshot.navigationRevision != _navigationRevision) {
      return;
    }
    final generation = ++_restoreGeneration;
    _scheduleRestore(snapshot, generation, 3);
  }

  void _scheduleRestore(
    ThreadPostViewportAnchorSnapshot snapshot,
    int generation,
    int remaining,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          generation != _restoreGeneration ||
          snapshot.navigationRevision != _navigationRevision) {
        return;
      }
      final controller = _scrollController;
      if (controller == null || !controller.hasClients) {
        return;
      }
      final position = controller.position;
      if (_isUserScrolling(position)) {
        return;
      }
      if (snapshot.wasAtLeadingEdge) {
        _jumpIfNeeded(controller, position.minScrollExtent);
        return;
      }

      final viewport = _viewportKey.currentContext?.findRenderObject();
      final pid = snapshot.pid;
      final post = pid == null
          ? null
          : (snapshot.chunkStartUnit == null
                    ? _postKeys[pid]
                    : _chunkKeys[pid]?[snapshot.chunkStartUnit])
                ?.currentContext
                ?.findRenderObject();
      if (viewport is RenderBox &&
          viewport.attached &&
          viewport.hasSize &&
          post is RenderBox &&
          post.attached &&
          post.hasSize) {
        final viewportTop = viewport.localToGlobal(Offset.zero).dy;
        final postTop = post.localToGlobal(Offset.zero).dy;
        final currentRelativeTop = postTop - viewportTop;
        final delta = currentRelativeTop - snapshot.relativeTop;
        _jumpIfNeeded(controller, position.pixels + delta);
        return;
      }
      if (snapshot.chunkStartUnit != null &&
          viewport is RenderBox &&
          viewport.hasSize) {
        // The new preceding block can temporarily push the desired block out
        // of the lazy window. Its actual end is the same target boundary.
        for (final entry
            in _chunkEnds[pid]?.entries ?? <MapEntry<int, int>>[]) {
          if (entry.value != snapshot.chunkStartUnit) continue;
          final previous = _chunkKeys[pid]?[entry.key]?.currentContext
              ?.findRenderObject();
          if (previous is! RenderBox ||
              !previous.attached ||
              !previous.hasSize) {
            continue;
          }
          final edge =
              previous.localToGlobal(Offset(0, previous.size.height)).dy -
              viewport.localToGlobal(Offset.zero).dy;
          _jumpIfNeeded(
            controller,
            position.pixels + edge - snapshot.relativeTop,
          );
          if (remaining > 0) {
            _scheduleRestore(snapshot, generation, remaining - 1);
          }
          return;
        }
        if (remaining > 0) {
          _scheduleRestore(snapshot, generation, remaining - 1);
          return;
        }
      }
      _jumpIfNeeded(controller, snapshot.scrollPixels);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _restoreGeneration += 1;
    _scrollController?.removeListener(_onScroll);
    _postKeys.clear();
    _chunkKeys.clear();
    _chunkEnds.clear();
  }

  void _onScroll() {
    final controller = _scrollController;
    if (_disposed || controller == null || !controller.hasClients) return;
    final pixels = controller.position.pixels;
    if (!_performingRestore && _lastPixels != null && pixels != _lastPixels) {
      _navigationRevision++;
      _restoreGeneration++;
    }
    _lastPixels = pixels;
  }

  bool _isUserScrolling(ScrollPosition position) {
    return position.isScrollingNotifier.value ||
        position.userScrollDirection != ScrollDirection.idle;
  }

  void _jumpIfNeeded(ScrollController controller, double requestedPixels) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final target = requestedPixels
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - target).abs() <= _pixelTolerance) {
      return;
    }
    _performingRestore = true;
    try {
      controller.jumpTo(target);
    } finally {
      _performingRestore = false;
    }
  }
}
