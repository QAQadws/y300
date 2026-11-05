import 'dart:async';

import 'package:flutter/widgets.dart';

/// Restores positions during viewport layout, before the new geometry paints.
class ReaderLayoutScrollController extends ScrollController {
  Future<bool> restore(double Function(ScrollMetrics) resolve) {
    if (!hasClients) return Future.value(false);
    return (position as _RestoringPosition).restore(resolve);
  }

  void cancelRestore() {
    for (final position in positions.cast<_RestoringPosition>()) {
      position.cancelRestore();
    }
  }

  /// Apply a measured displacement when the caller publishes the layout.
  /// Independent displacements from the same frame share one correction.
  void preserveWhileIdle(
    ScrollPosition expected, {
    required double delta,
    required bool Function() isCurrent,
  }) {
    if (positions.length != 1 ||
        !identical(position, expected) ||
        !delta.isFinite ||
        delta.abs() <= 0.001) {
      return;
    }
    (expected as _RestoringPosition).preserve(delta, isCurrent);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _RestoringPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _RestoringPosition extends ScrollPositionWithSingleContext {
  _RestoringPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  double Function(ScrollMetrics)? _resolve;
  Completer<bool>? _completion;
  int _corrections = 0;
  final _preservations = <({double delta, bool Function() isCurrent})>[];
  double _preservationOrigin = 0;
  int _preservationRevision = 0;

  Future<bool> restore(double Function(ScrollMetrics) resolve) {
    cancelRestore();
    _cancelPreservation();
    goIdle();
    _resolve = resolve;
    _corrections = 0;
    final completion = _completion = Completer<bool>();
    // Invalidate the viewport without jumping or starting a ballistic scroll.
    notifyListeners();
    WidgetsBinding.instance.ensureVisualUpdate();
    return completion.future;
  }

  void cancelRestore() {
    _resolve = null;
    _completion?.complete(false);
    _completion = null;
  }

  void preserve(double delta, bool Function() isCurrent) {
    if (_resolve != null || isScrollingNotifier.value) return;
    if (_preservations.isEmpty) {
      _corrections = 0;
      _preservationOrigin = pixels;
      addListener(_cancelPreservation);
      final revision = ++_preservationRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (revision == _preservationRevision) _cancelPreservation();
      });
    }
    _preservations.add((delta: delta, isCurrent: isCurrent));
  }

  void _cancelPreservation() {
    if (_preservations.isEmpty) return;
    removeListener(_cancelPreservation);
    _preservations.clear();
    _preservationRevision++;
  }

  double? _preservedPixels() {
    if (isScrollingNotifier.value) return null;
    double? target;
    for (final candidate in _preservations) {
      if (candidate.isCurrent()) {
        target = (target ?? _preservationOrigin) + candidate.delta;
      }
    }
    return target;
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final resolve = _resolve;
    double? target;
    if (resolve != null) {
      final metrics = FixedScrollMetrics(
        minScrollExtent: minScrollExtent,
        maxScrollExtent: maxScrollExtent,
        pixels: pixels,
        viewportDimension: viewportDimension,
        axisDirection: axisDirection,
        devicePixelRatio: devicePixelRatio,
      );
      target = resolve(metrics);
    } else {
      target = _preservedPixels();
    }
    final corrected = target?.clamp(minScrollExtent, maxScrollExtent);
    // Lazy extents refine after seeking. Bound the layout correction passes.
    if (corrected != null &&
        (corrected - pixels).abs() > 0.5 &&
        _corrections < 4) {
      _corrections++;
      correctPixels(corrected);
      return false;
    }
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    final completion = _completion;
    if (accepted && completion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!identical(_completion, completion)) return;
        _resolve = null;
        _completion = null;
        completion.complete(true);
      });
    }
    return accepted;
  }

  @override
  void dispose() {
    cancelRestore();
    _cancelPreservation();
    super.dispose();
  }
}
