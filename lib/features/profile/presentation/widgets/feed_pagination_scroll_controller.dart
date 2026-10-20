import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Coordinates a published page change with its list's return animation.
class FeedPaginationScrollController extends ScrollController {
  int _generation = 0;
  bool _returning = false;
  bool _disposed = false;

  Future<void> changePage({
    required Future<void> Function() load,
    required int? Function() currentPage,
    required bool Function() isCurrent,
    required bool Function() animate,
  }) async {
    if (_disposed || !isCurrent()) return;
    final previousPage = currentPage();
    if (previousPage == null) return;
    cancelReturn();
    final generation = _generation;
    bool current() => !_disposed && generation == _generation && isCurrent();

    await load();
    if (!current()) return;
    final page = currentPage();
    if (page == null || page == previousPage) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!current() || currentPage() != page || !hasClients) return;

    final target = position.minScrollExtent;
    if ((position.pixels - target).abs() < 0.5) return;
    if (!animate()) {
      jumpTo(target);
      return;
    }

    _returning = true;
    try {
      await animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (generation == _generation) _returning = false;
    }
  }

  bool handleScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      // Flutter has already handed control to the user. Retire queued work
      // without jumping, which would cancel the user's own drag activity.
      cancelReturn(stopAnimation: false);
    }
    return false;
  }

  void cancelReturn({bool stopAnimation = true}) {
    if (_disposed) return;
    _generation++;
    final wasReturning = _returning;
    _returning = false;
    if (stopAnimation && wasReturning && hasClients) {
      jumpTo(position.pixels);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
