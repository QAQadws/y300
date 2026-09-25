import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';

/// Keeps Scaffold's anchor in layout while only the overlay follows the finger.
class ReaderCornerDock extends StatefulWidget {
  const ReaderCornerDock({
    super.key,
    required this.side,
    required this.visible,
    required this.onSideChanged,
    required this.child,
    required this.feedbackBuilder,
    required this.dragHint,
    required this.moveLeftLabel,
    required this.moveRightLabel,
    required this.saveFailedLabel,
  });

  final ReaderCornerDockSide? side;
  final bool visible;
  final Future<bool> Function(ReaderCornerDockSide) onSideChanged;
  final Widget child;
  final Widget Function(double elevation) feedbackBuilder;
  final String dragHint;
  final String moveLeftLabel;
  final String moveRightLabel;
  final String saveFailedLabel;

  @override
  State<ReaderCornerDock> createState() => _ReaderCornerDockState();
}

class _ReaderCornerDockState extends State<ReaderCornerDock>
    with TickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();
  late final AnimationController _lift;
  late final AnimationController _snap;
  bool _dragging = false;
  bool _snapping = false;
  bool _snapStarted = false;
  bool _snapScheduled = false;
  bool _resetScheduled = false;
  int _flight = 0;
  MediaQueryData? _viewport;
  Offset _position = Offset.zero;
  Offset _dragOrigin = Offset.zero;
  Offset _snapFrom = Offset.zero;
  Offset _snapTo = Offset.zero;
  Rect _dragBounds = Rect.zero;
  Size _buttonSize = Size.zero;
  double _midpoint = 0;
  ReaderCornerDockSide _sourceSide = ReaderCornerDockSide.right;

  bool get _inFlight => _dragging || _snapping;
  bool get _visible => widget.visible && widget.side != null;
  bool get _animationsDisabled => MediaQuery.disableAnimationsOf(context);

  Offset get _feedbackPosition => _snapStarted
      ? Offset.lerp(
          _snapFrom,
          // Snackbars can keep moving the anchor during the snap. Follow its
          // live height so revealing the real button never produces a jump.
          Offset(_snapTo.dx, _anchorOffset().dy),
          Curves.easeOutCubic.transform(_snap.value),
        )!
      : _position;

  @override
  void initState() {
    super.initState();
    _lift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _snap =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 280),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _dismissFlight();
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = MediaQuery.of(context);
    final old = _viewport;
    _viewport = viewport;
    if (old != null &&
        (old.size != viewport.size ||
            old.padding != viewport.padding ||
            old.viewInsets != viewport.viewInsets ||
            old.disableAnimations != viewport.disableAnimations)) {
      _scheduleReset();
    }
  }

  @override
  void didUpdateWidget(covariant ReaderCornerDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_snapping && oldWidget.side != widget.side) _scheduleSnap();
    if (!_visible) {
      _scheduleReset();
    }
  }

  void _scheduleReset() {
    if (!_inFlight || _resetScheduled) return;
    _resetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _resetScheduled) _dismissFlight();
    });
  }

  RenderBox get _overlayBox =>
      Overlay.of(context).context.findRenderObject()! as RenderBox;

  Offset _anchorOffset() {
    final anchor = _anchorKey.currentContext!.findRenderObject()! as RenderBox;
    return _overlayBox.globalToLocal(anchor.localToGlobal(Offset.zero));
  }

  bool _captureFlight() {
    if (_inFlight || _resetScheduled || !_visible) return false;
    final side = widget.side;
    if (side == null) return false;
    final anchor = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchor == null || !anchor.hasSize || anchor.size.isEmpty) return false;
    final scaffold = Scaffold.of(context);
    final scaffoldBox = scaffold.context.findRenderObject()! as RenderBox;
    final origin = _overlayBox.globalToLocal(
      scaffoldBox.localToGlobal(Offset.zero),
    );
    final media = MediaQuery.of(scaffold.context);
    _buttonSize = anchor.size;
    _position = _dragOrigin = _anchorOffset();
    _sourceSide = side;
    _midpoint = origin.dx + scaffoldBox.size.width / 2;
    // Reserve the lifted surface's overhang, not just its unscaled hit box.
    final overhang = _buttonSize.width * 0.04;
    final left = origin.dx + media.padding.left + overhang;
    final top =
        origin.dy + (scaffold.appBarMaxHeight ?? media.padding.top) + overhang;
    _dragBounds = Rect.fromLTRB(
      left,
      top,
      math.max(
        left,
        origin.dx +
            scaffoldBox.size.width -
            media.padding.right -
            _buttonSize.width -
            overhang,
      ),
      math.max(
        top,
        origin.dy +
            scaffoldBox.size.height -
            math.max(media.viewInsets.bottom, media.padding.bottom) -
            _buttonSize.height -
            overhang,
      ),
    );
    _flight++;
    _snapStarted = false;
    return true;
  }

  void _startDrag(LongPressStartDetails details) {
    if (!_captureFlight()) return;
    setState(() => _dragging = true);
    _portal.show();
    if (_animationsDisabled) {
      _lift.value = 1;
    } else {
      unawaited(_lift.forward());
    }
    unawaited(HapticFeedback.selectionClick());
  }

  void _moveDrag(LongPressMoveUpdateDetails details) {
    if (!_dragging || _resetScheduled) return;
    final next = _dragOrigin + details.offsetFromOrigin;
    setState(() {
      _position = Offset(
        next.dx.clamp(_dragBounds.left, _dragBounds.right),
        next.dy.clamp(_dragBounds.top, _dragBounds.bottom),
      );
    });
  }

  void _endDrag(LongPressEndDetails details) {
    if (!_dragging || _resetScheduled) return;
    final distance = _position.dx + _buttonSize.width / 2 - _midpoint;
    final side = distance.abs() < 0.001
        ? _sourceSide
        : distance < 0
        ? ReaderCornerDockSide.left
        : ReaderCornerDockSide.right;
    _settle(side, persist: true);
  }

  void _cancelDrag() {
    if (_dragging && !_resetScheduled) {
      _settle(_sourceSide, persist: false);
    }
  }

  void _moveAccessibly(ReaderCornerDockSide side) {
    if (!_captureFlight()) return;
    _portal.show();
    _settle(side, persist: true);
  }

  void _settle(ReaderCornerDockSide side, {required bool persist}) {
    setState(() {
      _dragging = false;
      _snapping = true;
    });
    if (persist) unawaited(_saveSide(side));
    _scheduleSnap();
  }

  Future<void> _saveSide(ReaderCornerDockSide side) async {
    final saved = await widget.onSideChanged(side);
    if (!saved && mounted && ModalRoute.of(context)?.isCurrent != false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.saveFailedLabel)));
    }
  }

  void _scheduleSnap() {
    if (_snapScheduled || _resetScheduled) return;
    _snapScheduled = true;
    final flight = _flight;
    // The placeholder must first reach the new Scaffold anchor. Measuring that
    // actual layout also keeps snackbar and keyboard avoidance intact.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || flight != _flight) return;
      _snapScheduled = false;
      if (!_snapping || _resetScheduled) return;
      if (_animationsDisabled || !_visible) {
        _dismissFlight();
        return;
      }
      _snapFrom = _feedbackPosition;
      _snapTo = _anchorOffset();
      _snapStarted = true;
      unawaited(_lift.reverse());
      unawaited(_snap.forward(from: 0));
    });
  }

  void _dismissFlight() {
    _flight++;
    _snap.stop();
    _lift.stop();
    _lift.value = 0;
    _portal.hide();
    setState(() {
      _dragging = _snapping = _snapStarted = false;
      _snapScheduled = _resetScheduled = false;
    });
  }

  @override
  void dispose() {
    _snap.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.side;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => AnimatedBuilder(
        animation: Listenable.merge([_lift, _snap]),
        builder: (context, _) {
          if (!_visible || _resetScheduled) return const SizedBox.shrink();
          final position = _feedbackPosition;
          final lift = Curves.easeOutCubic.transform(_lift.value);
          return Positioned(
            left: position.dx,
            top: position.dy,
            width: _buttonSize.width,
            height: _buttonSize.height,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: TooltipVisibility(
                  visible: false,
                  child: Transform.scale(
                    scale: 1 + 0.08 * lift,
                    child: widget.feedbackBuilder(2 + 4 * lift),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      child: IgnorePointer(
        ignoring: _snapping || side == null || !_visible,
        child: Listener(
          onPointerCancel: (_) => _cancelDrag(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onLongPressStart: _startDrag,
            onLongPressMoveUpdate: _moveDrag,
            onLongPressEnd: _endDrag,
            onLongPressCancel: _cancelDrag,
            child: ExcludeSemantics(
              excluding: _inFlight || !_visible || side == null,
              child: Opacity(
                opacity: _inFlight ? 0 : 1,
                child: Semantics(
                  hint: widget.dragHint,
                  customSemanticsActions: {
                    if (side != ReaderCornerDockSide.left)
                      CustomSemanticsAction(label: widget.moveLeftLabel): () =>
                          _moveAccessibly(ReaderCornerDockSide.left),
                    if (side != ReaderCornerDockSide.right)
                      CustomSemanticsAction(label: widget.moveRightLabel): () =>
                          _moveAccessibly(ReaderCornerDockSide.right),
                  },
                  child: SizedBox(key: _anchorKey, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
