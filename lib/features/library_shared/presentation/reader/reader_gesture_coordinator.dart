import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

typedef ReaderDoubleTapListener = void Function(ReaderDoubleTapDetails details);
typedef ReaderPointerListener = void Function(PointerEvent event);

@immutable
class ReaderDoubleTapDetails {
  const ReaderDoubleTapDetails({
    required this.globalPosition,
    required this.timeStamp,
  });

  final Offset globalPosition;
  final Duration timeStamp;
}

/// Coordinates reader tap semantics without entering Flutter's gesture arena.
///
/// Scrollables remain the owners of one-finger drags. The coordinator only
/// commits a single-tap action after the double-tap window has elapsed and
/// routes a confirmed double tap to the active zoom surface.
class ReaderGestureCoordinator {
  ReaderGestureCoordinator({
    this.doubleTapTimeout = kDoubleTapTimeout,
    this.tapSlop = kTouchSlop,
    this.doubleTapSlop = kDoubleTapSlop,
  });

  final Duration doubleTapTimeout;
  final double tapSlop;
  final double doubleTapSlop;

  final Set<ReaderDoubleTapListener> _doubleTapListeners =
      <ReaderDoubleTapListener>{};
  final Set<ReaderPointerListener> _pointerListeners =
      <ReaderPointerListener>{};

  int? _activePointer;
  Offset? _downGlobalPosition;
  bool _candidateCancelled = false;
  bool _completesDoubleTap = false;
  bool _multiPointerSequence = false;

  Timer? _pendingSingleTapTimer;
  Offset? _pendingTapGlobalPosition;
  VoidCallback? _pendingSingleTapAction;
  bool _disposed = false;

  void addDoubleTapListener(ReaderDoubleTapListener listener) {
    _doubleTapListeners.add(listener);
  }

  void removeDoubleTapListener(ReaderDoubleTapListener listener) {
    _doubleTapListeners.remove(listener);
  }

  void addPointerListener(ReaderPointerListener listener) {
    _pointerListeners.add(listener);
  }

  void removePointerListener(ReaderPointerListener listener) {
    _pointerListeners.remove(listener);
  }

  void handlePointerDown(
    PointerDownEvent event, {
    required bool singleTapEnabled,
  }) {
    if (_disposed) {
      return;
    }
    _notifyPointer(event);
    if (_activePointer != null) {
      _candidateCancelled = true;
      _multiPointerSequence = true;
      return;
    }

    _activePointer = event.pointer;
    _downGlobalPosition = event.position;
    _candidateCancelled = false;
    _completesDoubleTap = _isDoubleTapCandidate(event.position);
    if (_completesDoubleTap) {
      _pendingSingleTapTimer?.cancel();
      _pendingSingleTapTimer = null;
      return;
    }

    if (!singleTapEnabled) {
      _pendingSingleTapAction = null;
    }
  }

  void handlePointerMove(PointerMoveEvent event) {
    if (_disposed) {
      return;
    }
    _notifyPointer(event);
    if (event.pointer != _activePointer || _candidateCancelled) {
      return;
    }
    final down = _downGlobalPosition;
    if (down == null || (event.position - down).distance > tapSlop) {
      _candidateCancelled = true;
    }
  }

  void handlePointerUp(
    PointerUpEvent event, {
    required VoidCallback? singleTapAction,
  }) {
    if (_disposed) {
      return;
    }
    _notifyPointer(event);
    if (event.pointer != _activePointer) {
      return;
    }
    final down = _downGlobalPosition;
    final isTap =
        !_candidateCancelled &&
        down != null &&
        (event.position - down).distance <= tapSlop;
    final completesDoubleTap = _completesDoubleTap;
    final multiPointerSequence = _multiPointerSequence;
    _resetPointerCandidate();

    if (!isTap) {
      if (completesDoubleTap && !multiPointerSequence) {
        _commitPendingSingleTap();
      } else {
        _clearPendingSingleTap();
      }
      return;
    }

    if (completesDoubleTap) {
      _clearPendingSingleTap();
      final details = ReaderDoubleTapDetails(
        globalPosition: event.position,
        timeStamp: event.timeStamp,
      );
      for (final listener in List<ReaderDoubleTapListener>.of(
        _doubleTapListeners,
      )) {
        listener(details);
      }
      return;
    }

    _clearPendingSingleTap();
    _pendingTapGlobalPosition = event.position;
    _pendingSingleTapAction = singleTapAction;
    _pendingSingleTapTimer = Timer(doubleTapTimeout, _commitPendingSingleTap);
  }

  void handlePointerCancel(PointerCancelEvent event) {
    if (_disposed) {
      return;
    }
    _notifyPointer(event);
    if (event.pointer != _activePointer) {
      return;
    }
    final completesDoubleTap = _completesDoubleTap;
    final multiPointerSequence = _multiPointerSequence;
    _resetPointerCandidate();
    if (completesDoubleTap && !multiPointerSequence) {
      _commitPendingSingleTap();
    } else if (completesDoubleTap) {
      _clearPendingSingleTap();
    }
  }

  void cancelPendingTap() {
    _clearPendingSingleTap();
    _resetPointerCandidate();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _clearPendingSingleTap();
    _doubleTapListeners.clear();
    _pointerListeners.clear();
    _resetPointerCandidate();
  }

  bool _isDoubleTapCandidate(Offset globalPosition) {
    final pendingPosition = _pendingTapGlobalPosition;
    return (_pendingSingleTapTimer?.isActive ?? false) &&
        pendingPosition != null &&
        (globalPosition - pendingPosition).distance <= doubleTapSlop;
  }

  void _notifyPointer(PointerEvent event) {
    for (final listener in List<ReaderPointerListener>.of(_pointerListeners)) {
      listener(event);
    }
  }

  void _commitPendingSingleTap() {
    final action = _pendingSingleTapAction;
    _clearPendingSingleTap();
    if (!_disposed) {
      action?.call();
    }
  }

  void _clearPendingSingleTap() {
    _pendingSingleTapTimer?.cancel();
    _pendingSingleTapTimer = null;
    _pendingTapGlobalPosition = null;
    _pendingSingleTapAction = null;
  }

  void _resetPointerCandidate() {
    _activePointer = null;
    _downGlobalPosition = null;
    _candidateCancelled = false;
    _completesDoubleTap = false;
    _multiPointerSequence = false;
  }
}
