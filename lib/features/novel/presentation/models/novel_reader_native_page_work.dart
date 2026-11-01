/// Numeric work observed while preparing one actual page delivery. Wall times
/// include cooperative waits; advance times include only synchronous calls,
/// not thread CPU time. Final view adoption/painting is outside these intervals.
/// Frame counts are explicit scheduler yields, not all elapsed engine frames.
/// This is neither a coverage proof nor a persistent/cache identity.
final class NovelReaderNativePageWork {
  const NovelReaderNativePageWork({
    required this.preparationUs,
    required this.coverageUs,
    required this.preparationAdvanceUs,
    required this.coverageAdvanceUs,
    required this.preparationFrames,
    required this.coverageFrames,
    required this.preparationSteps,
    required this.coverageSteps,
    required this.layoutsBuilt,
    required this.picturesBuilt,
    required this.checkedGraphemes,
  });
  final int preparationUs;
  final int coverageUs;
  final int preparationAdvanceUs;
  final int coverageAdvanceUs;
  final int preparationFrames;
  final int coverageFrames;
  final int preparationSteps;
  final int coverageSteps;
  final int layoutsBuilt;
  final int picturesBuilt;
  final int checkedGraphemes;
}
