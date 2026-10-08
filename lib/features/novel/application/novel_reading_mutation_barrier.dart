/// Manual chapter mutations retire already queued producer writes.
final class NovelReadingMutationBarrier {
  final Map<(String, String), int> _revisions = {};
  int capture(String novelId, String episodeId) =>
      _revisions[(novelId, episodeId)] ?? 0;
  bool isCurrent(String novelId, String episodeId, int revision) =>
      capture(novelId, episodeId) == revision;
  void invalidate(String novelId, String episodeId) {
    _revisions[(novelId, episodeId)] = capture(novelId, episodeId) + 1;
  }
}
