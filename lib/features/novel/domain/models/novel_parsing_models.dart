/// Phase 0 parsing signal for novel chapter discovery.
class NovelParsingSignal {
  const NovelParsingSignal({required this.stage, required this.message});

  final String stage;
  final String message;

  @override
  String toString() => '[$stage] $message';
}

/// Structured debug snapshot for one novel parsing run.
class NovelParsingDebugInfo {
  const NovelParsingDebugInfo({
    required this.totalAnchors,
    required this.totalOpPosts,
    required this.matchedChapterCandidates,
    required this.fallbackPagesVisited,
    required this.signals,
  });

  final int totalAnchors;
  final int totalOpPosts;
  final int matchedChapterCandidates;
  final int fallbackPagesVisited;
  final List<NovelParsingSignal> signals;
}
