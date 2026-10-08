enum NovelReadingSessionEntry {
  firstStart,
  explicitStart,
  resume,
  readOnlyRestore,
  bodyEnd,
}

/// Identifies one producer, including reopening the same chapter.
final class NovelReadingSessionToken {
  const NovelReadingSessionToken({
    required this.novelId,
    required this.episodeId,
    required this.generation,
    required this.entry,
  });

  final String novelId;
  final String episodeId;
  final int generation;
  final NovelReadingSessionEntry entry;
}

/// A queued write must recheck this guard inside its persistence transaction.
final class NovelReadingCommitLease {
  const NovelReadingCommitLease({
    required this.token,
    required this.revision,
    required this.isCurrent,
  });

  final NovelReadingSessionToken token;
  final int revision;
  final bool Function() isCurrent;

  bool get isValid => isCurrent();
}
