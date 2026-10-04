/// Waiting limits for a pagination request, independent of reading preferences.
///
/// The target deadline includes preparation. Once a target is readable, only
/// time without a newly published page counts toward the background deadline.
/// These configurable defaults are recovery limits, not device performance
/// claims. Individual HTML probes and cooperative work slices keep their own
/// smaller limits in the measurement adapter and planner.
final class NovelReaderPaginationPerformancePolicy {
  const NovelReaderPaginationPerformancePolicy({
    this.targetPageWait = const Duration(seconds: 5),
    this.backgroundIdle = const Duration(seconds: 2),
    this.enforceBudgets = true,
  });

  final Duration targetPageWait;
  final Duration backgroundIdle;
  final bool enforceBudgets;
}
