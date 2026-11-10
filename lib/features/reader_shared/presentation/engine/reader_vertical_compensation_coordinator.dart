import 'dart:async';

import 'package:continuous_image_geometry/continuous_image_geometry.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// Flutter lifecycle for already-planned geometry corrections. The geometry
/// package decides eligibility; the engine retains measurements and positions.
final class ReaderVerticalCompensationCoordinator {
  ReaderVerticalCompensationCoordinator({
    void Function(VoidCallback callback)? scheduleAfterFrame,
  }) : _scheduleAfterFrame = scheduleAfterFrame ?? _afterFrame;

  final void Function(VoidCallback) _scheduleAfterFrame;
  _VerticalCompensationBinding? _binding;
  ScrollPosition? _observedPosition;
  double _pendingDelta = 0;
  double _extentDeltaTotal = 0;
  double? _pageSpacing;
  Object? _spacingRequest;
  Object? _flushRequest;
  bool _closed = false;

  void bind({
    required Object session,
    required ScrollController controller,
    required bool Function() isCurrent,
  }) {
    if (_closed) return;
    final current = _binding;
    if (current != null &&
        identical(current.session, session) &&
        identical(current.controller, controller)) {
      return;
    }
    deactivate();
    _binding = _VerticalCompensationBinding(session, controller, isCurrent);
    syncPosition();
  }

  void syncPosition() {
    final binding = _current;
    final next = binding != null && binding.controller.hasClients
        ? binding.controller.position
        : null;
    if (identical(next, _observedPosition)) return;
    final previous = _observedPosition;
    previous?.isScrollingNotifier.removeListener(flushIfIdle);
    if (previous != null) cancelPending();
    _observedPosition = next;
    next?.isScrollingNotifier.addListener(flushIfIdle);
    flushIfIdle();
  }

  void applyPlan(ContinuousImageScrollCompensationPlan plan) {
    if (!plan.shouldCompensate ||
        !plan.delta.isFinite ||
        plan.delta.abs() <= 0.5 ||
        _current == null) {
      return;
    }
    syncPosition();
    if (_observedPosition == null) return;
    final total = _extentDeltaTotal + plan.delta;
    if (!total.isFinite) return;
    _extentDeltaTotal = total;
    _enqueue(plan.delta);
  }

  /// Capture the old stable item's absolute offset before the host publishes
  /// new gaps, then compare that same item after layout. Only the latest wins.
  void updatePageSpacing({
    required double pageSpacing,
    required double? Function() readAnchorOffset,
  }) {
    final binding = _current;
    if (binding == null || !pageSpacing.isFinite) return;
    final previous = _pageSpacing;
    _pageSpacing = pageSpacing;
    if (previous == null || (previous - pageSpacing).abs() < 0.001) return;
    final request = _spacingRequest = Object();
    final position = _position(binding);
    if (position == null) {
      _spacingRequest = null;
      return;
    }
    final oldOffset = readAnchorOffset();
    if (oldOffset == null || !oldOffset.isFinite) {
      _spacingRequest = null;
      flushIfIdle();
      return;
    }
    final extentTotalAtCapture = _extentDeltaTotal;
    _scheduleAfterFrame(() {
      if (!identical(_spacingRequest, request)) return;
      if (!_matches(binding, position)) {
        _spacingRequest = null;
        return;
      }
      final newOffset = readAnchorOffset();
      if (newOffset == null || !newOffset.isFinite) {
        _spacingRequest = null;
        flushIfIdle();
        return;
      }
      final commit = _spacingRequest = Object();
      // This anchor shift also contains extent changes from the same layout.
      // Wait for that frame's measurement callbacks, then count those once.
      scheduleMicrotask(() {
        if (!identical(_spacingRequest, commit)) return;
        _spacingRequest = null;
        if (!_matches(binding, position)) return;
        _enqueue(
          newOffset - oldOffset - (_extentDeltaTotal - extentTotalAtCapture),
        );
        flushIfIdle();
      });
    });
  }

  void _enqueue(double delta) {
    if (_current == null || !delta.isFinite || delta.abs() <= 0.5) return;
    syncPosition();
    if (_observedPosition == null) return;
    final pending = _pendingDelta + delta;
    if (!pending.isFinite) return;
    _pendingDelta = pending;
    flushIfIdle();
  }

  void flushIfIdle() {
    final binding = _current;
    if (binding == null || _flushRequest != null || _pendingDelta == 0) return;
    final position = _position(binding);
    if (position == null || !_idle(position)) return;
    final request = _flushRequest = Object();
    _scheduleAfterFrame(() {
      if (!identical(_flushRequest, request)) return;
      _flushRequest = null;
      if (!_matches(binding, position) ||
          !_idle(position) ||
          !position.hasContentDimensions ||
          _spacingRequest != null) {
        return;
      }
      // Sum first and clamp once against the post-layout viewport. An old
      // absolute target would discard other corrections or intervening motion.
      final delta = _pendingDelta;
      _pendingDelta = 0;
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() > 0.5) {
        binding.controller.jumpTo(target);
      }
    });
  }

  void cancelPending() {
    _pendingDelta = 0;
    _extentDeltaTotal = 0;
    _spacingRequest = null;
    _flushRequest = null;
  }

  void deactivate() {
    _observedPosition?.isScrollingNotifier.removeListener(flushIfIdle);
    _observedPosition = null;
    _binding = null;
    _pageSpacing = null;
    cancelPending();
  }

  void close() {
    _closed = true;
    deactivate();
  }

  _VerticalCompensationBinding? get _current {
    final binding = _binding;
    return !_closed && binding != null && binding.isCurrent() ? binding : null;
  }

  ScrollPosition? _position(_VerticalCompensationBinding binding) =>
      binding.controller.hasClients ? binding.controller.position : null;

  bool _matches(
    _VerticalCompensationBinding binding,
    ScrollPosition position,
  ) => identical(_current, binding) && identical(_position(binding), position);

  static bool _idle(ScrollPosition position) =>
      !position.isScrollingNotifier.value &&
      position.userScrollDirection == ScrollDirection.idle;

  static void _afterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

final class _VerticalCompensationBinding {
  _VerticalCompensationBinding(this.session, this.controller, this.isCurrent);
  final Object session;
  final ScrollController controller;
  final bool Function() isCurrent;
}
