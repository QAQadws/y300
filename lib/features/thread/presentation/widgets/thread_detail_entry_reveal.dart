import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Keeps the real lazy list mounted and laid out behind its entry surface.
/// Only bodies intersecting the viewport participate; media and cache-extent
/// bodies must not hold the first readable screen back.
class ThreadDetailEntryReveal extends StatefulWidget {
  const ThreadDetailEntryReveal({
    super.key,
    required this.loading,
    required this.failed,
    required this.loadingBuilder,
    required this.child,
    this.enabled = true,
    this.keepTitle = true,
    this.onRevealed,
  });

  final bool loading;
  final bool failed;
  final bool enabled;
  final bool keepTitle;
  final Widget Function(BuildContext context, double statusOpacity)
  loadingBuilder;
  final Widget child;
  final VoidCallback? onRevealed;

  @override
  State<ThreadDetailEntryReveal> createState() =>
      _ThreadDetailEntryRevealState();
}

class _ThreadDetailEntryRevealState extends State<ThreadDetailEntryReveal>
    with SingleTickerProviderStateMixin {
  final _viewport = GlobalKey();
  late final _readiness = _EntryReadiness(_scheduleCheck);
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  )..addStatusListener(_onFadeStatus);
  late Duration _waitingSince;
  bool _revealed = false;
  bool _finished = false;
  bool _hadReadableContent = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _waitingSince = SchedulerBinding.instance.currentFrameTimeStamp;
  }

  @override
  void didUpdateWidget(covariant ThreadDetailEntryReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading && !_hadReadableContent) {
      _revealed = false;
      _finished = false;
      _readiness.active = true;
      _fade.reset();
      _waitingSince = SchedulerBinding.instance.currentFrameTimeStamp;
    }
  }

  void _scheduleCheck() {
    if (_scheduled || _revealed || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _revealed || widget.loading || !widget.enabled) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      for (final body in _readiness.bodies) {
        if (!body.attached || !body.hasSize || body.ready()) continue;
        final top = body.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top < viewport.size.height && top + body.size.height >= 0) return;
      }
      _readiness.active = false;
      final elapsed =
          SchedulerBinding.instance.currentFrameTimeStamp - _waitingSince;
      final animate =
          !widget.failed &&
          !MediaQuery.disableAnimationsOf(context) &&
          elapsed >= const Duration(milliseconds: 300);
      setState(() {
        _revealed = true;
        _finished = !animate;
        if (!animate && !widget.failed) _hadReadableContent = true;
      });
      if (animate) {
        _fade.forward();
      } else {
        _fade.value = 1;
        if (!widget.failed) widget.onRevealed?.call();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _finished) return;
    setState(() {
      _finished = true;
      _hadReadableContent = true;
    });
    widget.onRevealed?.call();
  }

  @override
  void dispose() {
    _readiness.active = false;
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.loading ? widget.loadingBuilder(context, 1) : widget.child;
    }
    _scheduleCheck();
    final finished = _finished || widget.failed;
    return AnimatedBuilder(
      animation: _fade,
      child: _EntryReadinessScope(
        readiness: _readiness,
        hideTitle: !finished && widget.keepTitle,
        child: widget.child,
      ),
      builder: (context, child) => Stack(
        key: _viewport,
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: !finished,
            child: IgnorePointer(
              ignoring: !finished,
              child: ExcludeSemantics(
                excluding: !finished,
                child: Opacity(
                  key: const Key('thread-detail-entry-content'),
                  opacity: widget.failed ? 1 : _fade.value,
                  child: child,
                ),
              ),
            ),
          ),
          if (!finished || widget.loading)
            Opacity(
              opacity: widget.loading || widget.keepTitle ? 1 : 1 - _fade.value,
              child: widget.loadingBuilder(
                context,
                widget.loading ? 1 : 1 - _fade.value,
              ),
            ),
        ],
      ),
    );
  }
}

/// The overlay owns the title until the content fade completes. The real title
/// still lays out so its geometry and the mounted list never change at handoff.
class ThreadEntryTitle extends StatelessWidget {
  const ThreadEntryTitle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: _EntryReadinessScope.maybeOf(context)?.hideTitle == true ? 0 : 1,
    child: child,
  );
}

/// [ready] is sampled after child layout, including fwfh's async body build.
/// An error or empty body is a completed presentation too.
class ThreadEntryBody extends SingleChildRenderObjectWidget {
  const ThreadEntryBody({super.key, required this.ready, required super.child});

  final bool Function() ready;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _EntryBodyBox(_EntryReadinessScope.maybeOf(context)?.readiness, ready);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _EntryBodyBox;
    box.update(_EntryReadinessScope.maybeOf(context)?.readiness, ready);
  }
}

class _EntryReadiness {
  _EntryReadiness(this.onChanged);

  final VoidCallback onChanged;
  final bodies = <_EntryBodyBox>{};
  bool active = true;

  void changed() {
    if (active) onChanged();
  }
}

class _EntryReadinessScope extends InheritedWidget {
  const _EntryReadinessScope({
    required this.readiness,
    required this.hideTitle,
    required super.child,
  });

  final _EntryReadiness readiness;
  final bool hideTitle;

  static _EntryReadinessScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EntryReadinessScope>();

  @override
  bool updateShouldNotify(_EntryReadinessScope oldWidget) =>
      readiness != oldWidget.readiness || hideTitle != oldWidget.hideTitle;
}

class _EntryBodyBox extends RenderProxyBox {
  _EntryBodyBox(this.readiness, this.ready);

  _EntryReadiness? readiness;
  bool Function() ready;

  void update(_EntryReadiness? value, bool Function() isReady) {
    if (readiness != value && attached) {
      readiness?.bodies.remove(this);
      value?.bodies.add(this);
      readiness?.changed();
    }
    readiness = value;
    ready = isReady;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    readiness?.bodies.add(this);
    readiness?.changed();
  }

  @override
  void detach() {
    readiness?.bodies.remove(this);
    readiness?.changed();
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    readiness?.changed();
  }
}
