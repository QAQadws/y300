/// Debug signal captured during comic post parsing.
class ComicParsingSignal {
  const ComicParsingSignal({required this.stage, required this.message});

  final String stage;
  final String message;

  @override
  String toString() => '[$stage] $message';
}

/// Structured debug info for one parsing run.
class ComicParsingDebugInfo {
  const ComicParsingDebugInfo({
    required this.signals,
    required this.totalAnchors,
    required this.totalEpisodeLinks,
    this.catalogUrl,
  });

  final List<ComicParsingSignal> signals;
  final int totalAnchors;
  final int totalEpisodeLinks;
  final String? catalogUrl;
}
