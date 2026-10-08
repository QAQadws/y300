import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';

/// Measures mounted bodies only. The route owns visibility and persistence;
/// this object owns short-lived layout handles and the one initial restoration.
final class ThreadBodyReadingCoordinator {
  ThreadBodyReadingCoordinator({
    required this.observer,
    required this.scrollController,
    required this.initialTargetPid,
  });

  final ThreadBodyReadingObserver observer;
  final ScrollController scrollController;
  final String? initialTargetPid;
  final Map<Object, ThreadBodyReadingHandle> _bodies = {};
  GlobalKey? _viewportKey;
  Object? _contentIdentity;
  String _tid = '';
  int _page = 1;
  int _generation = 0;
  int _navigationRevision = 0;
  bool _scheduled = false;
  bool _disposed = false;
  bool _active = true;
  bool _userScroll = false;
  bool _restoreResolved = false;
  bool _restoring = false;
  ThreadBodyRestoreTarget? _pendingRestore;
  Object? _restoreBodyIdentity;
  int _restoreCorrections = 0;

  bool tracks(String tid, String pid) => observer.tracks(tid, pid);

  void bindContent({
    required String tid,
    required int page,
    required Object identity,
    required GlobalKey viewportKey,
  }) {
    _viewportKey = viewportKey;
    _tid = tid;
    _page = page;
    if (_contentIdentity != identity) {
      if (_contentIdentity != null && _pendingRestore != null) {
        _pendingRestore = null;
        _restoreResolved = true;
        _restoring = false;
      }
      _contentIdentity = identity;
      _generation++;
      _userScroll = false;
      observer.onContentChanged(identity);
    }
    schedule();
  }

  void register(ThreadBodyReadingHandle handle) {
    _bodies[handle.owner] = handle;
    schedule();
  }

  void unregister(Object owner) {
    _bodies.remove(owner);
    schedule();
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _generation++;
    if (!active && _pendingRestore != null) cancelRestore();
    if (active) schedule();
  }

  void handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_active || _disposed) return;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScroll = true;
      cancelRestore();
      observer.cancelPendingCompletion();
    }
    if (_userScroll &&
        notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0).abs() > 0) {
      _navigationRevision++;
    }
    if (notification is ScrollEndNotification) _userScroll = false;
    schedule();
  }

  void cancelRestore() {
    _restoreResolved = true;
    _pendingRestore = null;
    _restoring = false;
    _generation++;
  }

  void markUserNavigation() {
    if (_disposed) return;
    cancelRestore();
    _navigationRevision++;
    observer.cancelPendingCompletion();
    schedule();
  }

  void beginExplicitNavigation() {
    if (_disposed) return;
    cancelRestore();
    observer.cancelPendingCompletion();
  }

  void schedule() {
    if (_scheduled || _disposed || !_active) return;
    _scheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || !_active) return;
      if (generation != _generation) {
        schedule();
        return;
      }
      _sample();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _sample() {
    final viewport = _viewportKey?.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        !viewport.attached ||
        !viewport.hasSize ||
        !scrollController.hasClients ||
        _contentIdentity == null) {
      return;
    }
    final height = viewport.size.height;
    if (!height.isFinite || height <= 0) return;
    final samples = <ThreadBodyReadingSample>[];
    for (final handle in _bodies.values.toList(growable: false)) {
      if (handle.tid != _tid || !observer.tracks(handle.tid, handle.pid)) {
        continue;
      }
      final body = handle.key.currentContext?.findRenderObject();
      if (body is! RenderBox || !body.attached || !body.hasSize) continue;
      final top = body.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bodyHeight = body.size.height;
      if (!top.isFinite || !bodyHeight.isFinite || bodyHeight <= 0) continue;
      if (!_restoreResolved && handle.pid == initialTargetPid?.trim()) {
        // HTML preparation can temporarily expose a loading box. Wait for the
        // actual column before interpreting any saved body percentage.
        if (!handle.htmlReady() || !handle.imagesReady(viewport)) continue;
        final target = observer.restoreTarget(
          tid: _tid,
          pid: handle.pid,
          bodyIdentity: handle.bodyIdentity,
        );
        _restoreResolved = true;
        if (target != null &&
            target.fraction.isFinite &&
            target.fraction > 0 &&
            target.fraction <= 1 &&
            !_userScroll) {
          _pendingRestore = target;
          _restoreBodyIdentity = handle.bodyIdentity;
        }
      }
      if (_pendingRestore != null && handle.pid == initialTargetPid?.trim()) {
        if (_restoreBodyIdentity != handle.bodyIdentity || _userScroll) {
          _pendingRestore = null;
        } else {
          _restoring = true;
          if (!handle.htmlReady() || !handle.imagesReady(viewport)) continue;
          final position = scrollController.position;
          final range = math.max(0.0, bodyHeight - height);
          final desired =
              (position.pixels + top + _pendingRestore!.fraction * range)
                  .clamp(position.minScrollExtent, position.maxScrollExtent)
                  .toDouble();
          if ((desired - position.pixels).abs() > 0.5 &&
              _restoreCorrections < 3) {
            _restoreCorrections++;
            scrollController.jumpTo(desired);
            schedule();
            return;
          }
          _pendingRestore = null;
          _restoring = false;
        }
      }
      final visible = math.max(
        0.0,
        math.min(height, top + bodyHeight) - math.max(0.0, top),
      );
      if (visible <= 0) continue;
      final ready = handle.htmlReady() && handle.imagesReady(viewport);
      samples.add(
        ThreadBodyReadingSample(
          tid: _tid,
          pid: handle.pid,
          bodyIdentity: handle.bodyIdentity,
          relativeBodyTop: top,
          bodyHeight: bodyHeight,
          effectiveViewportHeight: height,
          visibleExtent: visible,
          bodyReady: ready,
          finalBoundaryKnown: ready && handle.finalBoundaryKnown(),
          geometryIdentity: (
            handle.bodyIdentity,
            body.size,
            viewport.size,
            handle.layoutRevision(),
          ),
        ),
      );
    }
    observer.onViewport(
      ThreadBodyReadingViewport(
        contentIdentity: _contentIdentity!,
        tid: _tid,
        page: _page,
        samples: List.unmodifiable(samples),
        idle:
            !_userScroll &&
            !scrollController.position.isScrollingNotifier.value &&
            !_restoring,
        restoreSettled:
            (_restoreResolved || initialTargetPid == null) && !_restoring,
        userNavigationRevision: _navigationRevision,
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _bodies.clear();
  }
}

final class ThreadBodyReadingHandle {
  const ThreadBodyReadingHandle({
    required this.owner,
    required this.key,
    required this.tid,
    required this.pid,
    required this.bodyIdentity,
    required this.htmlReady,
    required this.imagesReady,
    required this.finalBoundaryKnown,
    required this.layoutRevision,
  });

  final Object owner;
  final GlobalKey key;
  final String tid;
  final String pid;
  final Object bodyIdentity;
  final bool Function() htmlReady;
  final bool Function(RenderBox viewport) imagesReady;
  final bool Function() finalBoundaryKnown;
  final Object Function() layoutRevision;
}

/// Reports layout changes without constraining the body or building distant
/// posts. A generation check in the coordinator rejects retired callbacks.
class ThreadBodyReadingBoundary extends SingleChildRenderObjectWidget {
  const ThreadBodyReadingBoundary({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final ThreadBodyReadingCoordinator coordinator;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ReadingBodyBox(coordinator);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _ReadingBodyBox).coordinator = coordinator;
  }
}

class _ReadingBodyBox extends RenderProxyBox {
  _ReadingBodyBox(this.coordinator);
  ThreadBodyReadingCoordinator coordinator;

  @override
  void performLayout() {
    super.performLayout();
    coordinator.schedule();
  }
}
