/// Sampling controls for the isolated synthetic profile target, never App prefs.
final class NovelProfileBaselineConfig {
  const NovelProfileBaselineConfig({
    this.warmupsPerFixture = 5,
    this.opensPerFixture = 30,
    this.turnGroups = 3,
    this.turnsPerGroup = 200,
  });
  final int warmupsPerFixture;
  final int opensPerFixture;
  final int turnGroups;
  final int turnsPerGroup;

  void validate() {
    if ([
      warmupsPerFixture,
      opensPerFixture,
      turnGroups,
      turnsPerGroup,
    ].any((value) => value <= 0)) {
      throw ArgumentError('Profile sample counts must be positive');
    }
  }

  bool get hasRequiredSampleCounts =>
      warmupsPerFixture >= 5 &&
      opensPerFixture >= 30 &&
      turnGroups >= 3 &&
      turnsPerGroup >= 200;

  Map<String, Object> toJson() => {
    'warmupsPerFixture': warmupsPerFixture,
    'opensPerFixture': opensPerFixture,
    'turnGroups': turnGroups,
    'turnsPerGroup': turnsPerGroup,
    // Counts alone do not prove device, timing, correctness or memory gates.
    'hasRequiredSampleCounts': hasRequiredSampleCounts,
  };
}

bool profileBaselineCompleted({
  required NovelProfileBaselineConfig config,
  required int successfulWarmups,
  required int successfulOpens,
  required List<int> completedTurns,
}) =>
    successfulWarmups == config.warmupsPerFixture * 2 &&
    successfulOpens == config.opensPerFixture * 2 &&
    completedTurns.length == config.turnGroups &&
    completedTurns.every((count) => count == config.turnsPerGroup);

/// Bounce within one completed chapter, never ask the reader to switch chapters.
({int page, bool forward})? nextProfileTurn({
  required int currentPage,
  required int pageCount,
  required bool forward,
}) {
  if (pageCount < 0 || currentPage < 0 || currentPage >= pageCount) {
    throw ArgumentError('Invalid profile page range');
  }
  if (pageCount < 2) return null;
  final direction = currentPage == 0
      ? true
      : currentPage == pageCount - 1
      ? false
      : forward;
  return (page: currentPage + (direction ? 1 : -1), forward: direction);
}
