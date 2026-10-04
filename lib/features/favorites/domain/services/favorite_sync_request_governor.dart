// Adjust this single constant when tuning favorite sync request pacing.
// Applies to ALL favorite sync modes (first / automatic-resume / manual
// recent-add) — every governed parse request waits this long after the
// previous one completes, to avoid tripping the site's temporary IP ban.
const Duration favoriteSyncGovernorCooldown = Duration(milliseconds: 700);

enum FavoriteSyncExecutionMode {
  bootstrapInitial,
  automaticResume,
  manualRecentAdd,
}

enum FavoriteSyncRequestKind {
  favoriteListPage,
  favoriteThreadDetail,
  comicThreadDetail,
  comicCatalogHtml,
  // 注意：漫画论坛搜索由 ForumSearchReadScheduler（~10.5s 节奏）独立管控，
  // 不再走 favorite sync governor 的槽。这里删掉旧的 comicForumSearch
  // 枚举项以避免误用。
  novelSeedDetail,
  novelEpisodePage,
}

class FavoriteSyncExecutionContext {
  const FavoriteSyncExecutionContext({required this.mode, this.governor});

  const FavoriteSyncExecutionContext.bootstrapInitial({
    required FavoriteSyncRequestGovernor governor,
  }) : this(
         mode: FavoriteSyncExecutionMode.bootstrapInitial,
         governor: governor,
       );

  // Subsequent syncs are governed too: the same request pacing must apply so a
  // resume / manual add can't burst-fire parse requests and trip an IP ban.
  const FavoriteSyncExecutionContext.automaticResume({
    FavoriteSyncRequestGovernor? governor,
  }) : this(
         mode: FavoriteSyncExecutionMode.automaticResume,
         governor: governor,
       );

  const FavoriteSyncExecutionContext.manualRecentAdd({
    FavoriteSyncRequestGovernor? governor,
  }) : this(
         mode: FavoriteSyncExecutionMode.manualRecentAdd,
         governor: governor,
       );

  final FavoriteSyncExecutionMode mode;
  final FavoriteSyncRequestGovernor? governor;

  bool get isBootstrapInitial =>
      mode == FavoriteSyncExecutionMode.bootstrapInitial;
}

abstract interface class FavoriteSyncRequestGovernor {
  Future<T> run<T>({
    required FavoriteSyncRequestKind kind,
    required Future<T> Function() action,
  });
}
