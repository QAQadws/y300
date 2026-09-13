import 'dart:async';

import 'package:flutter/widgets.dart';

/// Restores before paint instead of using jumpTo's overscroll/ballistic path.
/// The caller keeps its loading surface until the returned future completes.
class NovelReaderScrollController extends ScrollController {
  Future<bool> restore(double Function(ScrollMetrics) resolve) {
    if (!hasClients) return Future.value(false);
    return (position as _RestoringPosition).restore(resolve);
  }

  void cancelRestore() {
    for (final position in positions.cast<_RestoringPosition>()) {
      position.cancelRestore();
    }
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

  Future<bool> restore(double Function(ScrollMetrics) resolve) {
    cancelRestore();
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

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final resolve = _resolve;
    if (resolve != null) {
      final metrics = FixedScrollMetrics(
        minScrollExtent: minScrollExtent,
        maxScrollExtent: maxScrollExtent,
        pixels: pixels,
        viewportDimension: viewportDimension,
        axisDirection: axisDirection,
        devicePixelRatio: devicePixelRatio,
      );
      final target = resolve(metrics).clamp(minScrollExtent, maxScrollExtent);
      // Lazy extents refine after seeking. Bound correction passes so unusually
      // heterogeneous blocks cannot trap the viewport in a layout loop.
      if ((target - pixels).abs() > 0.5 && _corrections < 4) {
        _corrections++;
        correctPixels(target.toDouble());
        return false;
      }
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
    super.dispose();
  }
}
