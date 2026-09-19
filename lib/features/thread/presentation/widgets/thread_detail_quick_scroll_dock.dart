import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/thread_quick_scroll_preferences_controller.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_quick_scroll_button.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Keeps Scaffold's anchor in layout while only the overlay follows the finger.
class ThreadDetailQuickScrollDock extends ConsumerStatefulWidget {
  const ThreadDetailQuickScrollDock({
    super.key,
    required this.coordinator,
    required this.hasContent,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final ThreadDetailQuickScrollCoordinator coordinator;
  final bool hasContent;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  ConsumerState<ThreadDetailQuickScrollDock> createState() =>
      _ThreadDetailQuickScrollDockState();
}

class _ThreadDetailQuickScrollDockState
    extends ConsumerState<ThreadDetailQuickScrollDock>
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
  ThreadQuickScrollDockSide _sourceSide = ThreadQuickScrollDockSide.right;

  bool get _inFlight => _dragging || _snapping;
  bool get _visible => widget.hasContent && widget.coordinator.isScrollable;
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
    widget.coordinator.addListener(_onScrollStateChanged);
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
  void didUpdateWidget(covariant ThreadDetailQuickScrollDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coordinator != oldWidget.coordinator) {
      oldWidget.coordinator.removeListener(_onScrollStateChanged);
      widget.coordinator.addListener(_onScrollStateChanged);
      _scheduleReset();
    }
    if (!_visible) {
      _scheduleReset();
    }
  }

  void _onScrollStateChanged() {
    if (!_visible) {
      _scheduleReset();
    }
    setState(() {});
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
    final side = ref.read(threadQuickScrollPreferencesControllerProvider).value;
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
        ? ThreadQuickScrollDockSide.left
        : ThreadQuickScrollDockSide.right;
    _settle(side, persist: true);
  }

  void _cancelDrag() {
    if (_dragging && !_resetScheduled) {
      _settle(_sourceSide, persist: false);
    }
  }

  void _moveAccessibly(ThreadQuickScrollDockSide side) {
    if (!_captureFlight()) return;
    _portal.show();
    _settle(side, persist: true);
  }

  void _settle(ThreadQuickScrollDockSide side, {required bool persist}) {
    setState(() {
      _dragging = false;
      _snapping = true;
    });
    if (persist) unawaited(_saveSide(side));
    _scheduleSnap();
  }

  Future<void> _saveSide(ThreadQuickScrollDockSide side) async {
    final saved = await ref
        .read(threadQuickScrollPreferencesControllerProvider.notifier)
        .setSide(side);
    if (!saved && mounted && ModalRoute.of(context)?.isCurrent != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).threadQuickScrollPositionSaveFailed,
          ),
        ),
      );
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
    widget.coordinator.removeListener(_onScrollStateChanged);
    _snap.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = ref
        .watch(threadQuickScrollPreferencesControllerProvider)
        .value;
    ref.listen(threadQuickScrollPreferencesControllerProvider, (
      previous,
      next,
    ) {
      if (_snapping && previous?.value != next.value) _scheduleSnap();
    });
    final l10n = AppLocalizations.of(context);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => AnimatedBuilder(
        animation: Listenable.merge([_lift, _snap, widget.coordinator]),
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
                    child: ThreadDetailQuickScrollButton(
                      surfaceKey: const Key(
                        'thread-quick-scroll-drag-feedback',
                      ),
                      coordinator: widget.coordinator,
                      hasContent: widget.hasContent,
                      backgroundColor: widget.backgroundColor,
                      foregroundColor: widget.foregroundColor,
                      elevation: 2 + 4 * lift,
                    ),
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
                  hint: l10n.threadQuickScrollDragHint,
                  customSemanticsActions: {
                    if (side != ThreadQuickScrollDockSide.left)
                      CustomSemanticsAction(
                        label: l10n.threadQuickScrollMoveLeft,
                      ): () =>
                          _moveAccessibly(ThreadQuickScrollDockSide.left),
                    if (side != ThreadQuickScrollDockSide.right)
                      CustomSemanticsAction(
                        label: l10n.threadQuickScrollMoveRight,
                      ): () =>
                          _moveAccessibly(ThreadQuickScrollDockSide.right),
                  },
                  child: SizedBox(
                    key: _anchorKey,
                    child: ThreadDetailQuickScrollButton(
                      coordinator: widget.coordinator,
                      hasContent: side != null && widget.hasContent,
                      backgroundColor: widget.backgroundColor,
                      foregroundColor: widget.foregroundColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
