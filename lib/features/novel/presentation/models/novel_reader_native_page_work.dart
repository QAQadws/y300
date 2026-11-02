/// Numeric work observed while preparing one actual page delivery. Wall times
/// include cooperative waits; advance times include only synchronous calls,
/// not thread CPU time. Final view adoption/painting is outside these intervals.
/// Advance totals are cumulative across calls, not the slowest individual call.
/// Frame counts are explicit scheduler yields, not all elapsed engine frames.
/// This is neither a coverage proof nor a persistent/cache identity.
final class NovelReaderNativePageWork {
  const NovelReaderNativePageWork({
    required this.preparationUs,
    required this.coverageUs,
    required this.preparationAdvances,
    required this.coverageAdvances,
    required this.preparationFrames,
    required this.coverageFrames,
    required this.layoutsBuilt,
    required this.picturesBuilt,
    required this.checkedGraphemes,
  });
  final int preparationUs;
  final int coverageUs;
  final NovelReaderNativeAdvanceWork preparationAdvances;
  final NovelReaderNativeAdvanceWork coverageAdvances;
  int get preparationAdvanceUs => preparationAdvances.totalUs;
  int get coverageAdvanceUs => coverageAdvances.totalUs;
  final int preparationFrames;
  final int coverageFrames;
  int get preparationSteps => preparationAdvances.steps;
  int get coverageSteps => coverageAdvances.steps;
  final int layoutsBuilt;
  final int picturesBuilt;
  final int checkedGraphemes;
}

/// Measured synchronous advances only. An over-budget call exceeds the entire
/// configured scheduling slice by itself; this is not a frame/raster measurement
/// and does not change admission, deadlines or scheduling decisions.
final class NovelReaderNativeAdvanceWork {
  const NovelReaderNativeAdvanceWork({
    required this.budgetUs,
    required this.steps,
    required this.totalUs,
    required this.maxUs,
    required this.overBudgetSteps,
  });
  final int budgetUs;
  final int steps;
  final int totalUs;
  final int maxUs;
  final int overBudgetSteps;
}
