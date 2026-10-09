/// Manual reading mutations retire already queued producer writes.
final class NovelReadingMutationBarrier {
  final Map<(String, String), int> _revisions = {};
  final Map<String, int> _workResetRevisions = {};
  final Map<String, int> _workMutationRevisions = {};
  int _nextRevision = 0;

  int capture(String novelId, String episodeId) {
    final chapterRevision = _revisions[(novelId, episodeId)] ?? 0;
    final workRevision = _workResetRevisions[novelId] ?? 0;
    return chapterRevision > workRevision ? chapterRevision : workRevision;
  }

  bool isCurrent(String novelId, String episodeId, int revision) =>
      capture(novelId, episodeId) == revision;

  void invalidate(String novelId, String episodeId) {
    final revision = ++_nextRevision;
    _revisions[(novelId, episodeId)] = revision;
    _workMutationRevisions[novelId] = revision;
  }

  // The work epoch also retires chapters that have no persisted row, including
  // a producer still waiting for its first visible body or first commit.
  void invalidateWork(String novelId) {
    final revision = ++_nextRevision;
    _workResetRevisions[novelId] = revision;
    _workMutationRevisions[novelId] = revision;
  }

  int captureWork(String novelId) => _workMutationRevisions[novelId] ?? 0;

  bool isWorkCurrent(String novelId, int revision) =>
      captureWork(novelId) == revision;
}
