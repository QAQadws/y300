import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final class ThreadPostViewportAnchorSnapshot {
  const ThreadPostViewportAnchorSnapshot({
    required this.pid,
    required this.relativeTop,
    required this.scrollPixels,
    required this.wasAtLeadingEdge,
  });

  final String? pid;
  final double relativeTop;
  final double scrollPixels;
  final bool wasAtLeadingEdge;
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
       _viewportKey = viewportKey;

  ScrollController? _scrollController;
  final GlobalKey _viewportKey;
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  int _restoreGeneration = 0;
  bool _disposed = false;
  static const double _pixelTolerance = 0.5;

  GlobalKey keyForPid(String pid) {
    final normalized = pid.trim();
    return _postKeys.putIfAbsent(
      normalized,
      () => GlobalKey(debugLabel: 'thread-post-anchor-$normalized'),
    );
  }

  void updateScrollController(ScrollController? scrollController) {
    _scrollController = scrollController;
    _restoreGeneration += 1;
  }

  void prune(Iterable<String> activePids) {
    final active = activePids.map((pid) => pid.trim()).toSet();
    _postKeys.removeWhere((pid, _) => !active.contains(pid));
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

    for (final rawPid in orderedPids) {
      final pid = rawPid.trim();
      final renderObject = _postKeys[pid]?.currentContext?.findRenderObject();
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
      if (top < firstVisibleTop) {
        firstVisibleTop = top;
        firstVisiblePid = pid;
      }
    }

    final position = controller.position;
    return ThreadPostViewportAnchorSnapshot(
      pid: firstVisiblePid,
      relativeTop: firstVisiblePid == null ? 0 : firstVisibleTop - viewportTop,
      scrollPixels: position.pixels,
      wasAtLeadingEdge:
          position.pixels <= position.minScrollExtent + _pixelTolerance,
    );
  }

  void restoreAfterFrame(ThreadPostViewportAnchorSnapshot? snapshot) {
    if (snapshot == null || _disposed) {
      return;
    }
    final generation = ++_restoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || generation != _restoreGeneration) {
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
          : _postKeys[pid]?.currentContext?.findRenderObject();
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
      _jumpIfNeeded(controller, snapshot.scrollPixels);
    });
  }

  void dispose() {
    _disposed = true;
    _restoreGeneration += 1;
    _postKeys.clear();
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
    controller.jumpTo(target);
  }
}
