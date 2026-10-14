import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

/// The page retains display choices and completed geometry, not mounted bodies.
final class ThreadBodyPresentationStore {
  final _bodies = <String, ThreadBodyPresentation>{};

  int get length => _bodies.length;

  ThreadBodyPresentation obtain(String pid, String html) {
    final previous = _bodies[pid];
    if (previous != null && previous.isActive && previous.html == html) {
      return previous;
    }
    previous?.dispose();
    return _bodies[pid] = ThreadBodyPresentation._(html);
  }

  void retainWhere(bool Function(String pid, String html) retain) {
    _bodies.removeWhere((pid, body) {
      if (retain(pid, body.html)) return false;
      body.dispose();
      return true;
    });
  }

  void remove(String pid) => _bodies.remove(pid)?.dispose();

  void clear() {
    for (final body in _bodies.values) {
      body.dispose();
    }
    _bodies.clear();
  }
}

/// Existing renderer presentation also retains its latest prepared-HTML layout
/// revisions. Those pure strings remain page-owned; DOM and Widgets do not.
final class ThreadBodyPresentation {
  ThreadBodyPresentation._(this.html);

  final String html;
  ForumHtmlBodyPresentation _rendering = ForumHtmlBodyPresentation();
  Object? _layoutIdentity;
  Object? _consumer;
  ThreadBodyLayoutLease? _lease;
  double? _height;
  bool _active = true;

  bool get isActive => _active;

  ThreadBodyLayoutLease bind({
    required Object consumer,
    required Object layoutIdentity,
  }) {
    if (!_active) throw StateError('Body presentation is retired');
    final changed = _layoutIdentity != layoutIdentity;
    if (!changed && identical(_consumer, consumer) && _lease != null) {
      return _lease!;
    }
    if (changed) {
      _height = null;
      if (_layoutIdentity != null) {
        final expansion = Map<String, bool>.of(_rendering.collapseExpansion);
        _rendering.dispose();
        _rendering = ForumHtmlBodyPresentation()
          ..collapseExpansion.addAll(expansion);
      }
    }
    _layoutIdentity = layoutIdentity;
    _consumer = consumer;
    return _lease = ThreadBodyLayoutLease._(this, _rendering);
  }

  bool _isCurrent(ThreadBodyLayoutLease lease) =>
      _active && identical(_lease, lease);

  void _release(ThreadBodyLayoutLease lease) {
    if (!_isCurrent(lease)) return;
    _lease = null;
    _consumer = null;
  }

  void dispose() {
    _active = false;
    _lease = null;
    _consumer = null;
    _layoutIdentity = null;
    _height = null;
    _rendering.dispose();
  }
}

/// Rebinding a body or its actual layout retires every previous measurement.
final class ThreadBodyLayoutLease {
  ThreadBodyLayoutLease._(this._body, this.rendering);

  final ThreadBodyPresentation _body;
  final ForumHtmlBodyPresentation rendering;

  bool get isCurrent => _body._isCurrent(this);
  double? get height => isCurrent ? _body._height : null;

  void recordHeight(double height) {
    if (isCurrent && height.isFinite && height > 0) _body._height = height;
  }

  void release() => _body._release(this);
}

enum ThreadBodyLayoutPhase { preparing, built, failed }

/// Keeps the last completed body height through both preparation and fwfh's
/// asynchronous build. It never constrains the completed renderer or scrolls.
class ThreadBodyWaitingLayout extends SingleChildRenderObjectWidget {
  const ThreadBodyWaitingLayout({
    super.key,
    required this.lease,
    required this.phase,
    required super.child,
  });

  final ThreadBodyLayoutLease lease;
  final ThreadBodyLayoutPhase Function() phase;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _WaitingBodyBox(lease, phase);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _WaitingBodyBox)
      ..lease = lease
      ..phase = phase
      ..markNeedsLayout();
  }
}

class _WaitingBodyBox extends RenderProxyBox {
  _WaitingBodyBox(this.lease, this.phase);

  ThreadBodyLayoutLease lease;
  ThreadBodyLayoutPhase Function() phase;

  @override
  void performLayout() {
    super.performLayout();
    if (!lease.isCurrent) return;
    switch (phase()) {
      case ThreadBodyLayoutPhase.built:
        lease.recordHeight(size.height);
      case ThreadBodyLayoutPhase.preparing:
        final height = lease.height;
        if (height != null) {
          size = constraints.constrain(Size(size.width, height));
        }
      case ThreadBodyLayoutPhase.failed:
        break;
    }
  }
}
