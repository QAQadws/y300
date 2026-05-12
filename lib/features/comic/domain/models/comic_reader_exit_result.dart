/// Result returned when leaving the comic reader.
///
/// The unified detail page only needs to reload local state today, but keeping
/// a typed result available lets future routes refresh narrower slices without
/// coupling detail UI to reader internals.
class ComicReaderExitResult {
  const ComicReaderExitResult({
    required this.comicId,
    required this.lastReadEpisodeId,
    this.completedEpisodeIds = const <String>[],
    this.shouldOpenEpisode = false,
  });

  final String comicId;
  final String lastReadEpisodeId;
  final List<String> completedEpisodeIds;

  /// Legacy adjacent navigation used this result to ask detail page to open
  /// another reader.  Phase 5 handles adjacent chapters inside the reader, so
  /// normal exits keep this false.
  final bool shouldOpenEpisode;
}
