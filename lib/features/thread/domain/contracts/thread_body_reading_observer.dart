/// Optional route-owned consumer of native post body positions. Ordinary forum
/// browsing does not install a consumer or create a reading history.
abstract interface class ThreadBodyReadingObserver {
  bool tracks(String tid, String pid);

  ThreadBodyRestoreTarget? restoreTarget({
    required String tid,
    required String pid,
    required Object bodyIdentity,
  });

  void onContentChanged(Object contentIdentity);
  void onViewport(ThreadBodyReadingViewport viewport);
  void onVisibility({required bool frontmost, required bool resumed});
  void cancelPendingCompletion();
  Future<void> flush();
  void retire();
}

/// Synchronously closes report admission while preserving the last confirmed
/// position's lease for an awaited flush. Visibility is retired afterwards.
abstract interface class ThreadBodyReadingSuspension {
  void suspendForFlush();
}

final class ThreadBodyRestoreTarget {
  const ThreadBodyRestoreTarget({
    required this.fraction,
    required this.requestIdentity,
  });

  final double fraction;
  final Object requestIdentity;
}

final class ThreadBodyReadingViewport {
  const ThreadBodyReadingViewport({
    required this.contentIdentity,
    required this.tid,
    required this.page,
    required this.samples,
    required this.idle,
    required this.restoreSettled,
    required this.userNavigationRevision,
  });

  final Object contentIdentity;
  final String tid;
  final int page;
  final List<ThreadBodyReadingSample> samples;
  final bool idle;
  final bool restoreSettled;
  final int userNavigationRevision;
}

final class ThreadBodyReadingSample {
  const ThreadBodyReadingSample({
    required this.tid,
    required this.pid,
    required this.bodyIdentity,
    required this.relativeBodyTop,
    required this.bodyHeight,
    required this.effectiveViewportHeight,
    required this.visibleExtent,
    required this.bodyReady,
    required this.finalBoundaryKnown,
    required this.geometryIdentity,
  });

  final String tid;
  final String pid;
  final Object bodyIdentity;
  // This coordinate is relative to the real viewport, including the negative
  // space used by a PID-centered CustomScrollView.
  final double relativeBodyTop;
  final double bodyHeight;
  final double effectiveViewportHeight;
  final double visibleExtent;
  final bool bodyReady;
  final bool finalBoundaryKnown;
  final Object geometryIdentity;
}
