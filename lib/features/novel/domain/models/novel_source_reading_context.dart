import 'novel_reading_session.dart';

/// An explicit catalog binding supplied by a novel entry point. Forum routes
/// cannot infer this ownership from a thread title, author or page number.
final class NovelSourceReadingContext {
  NovelSourceReadingContext({
    required this.novelId,
    required Iterable<NovelSourceReadingChapter> chapters,
    this.initialEpisodeId,
    this.entry = NovelReadingSessionEntry.resume,
  }) : chapters = List.unmodifiable(chapters) {
    final bySource = <(String, String), NovelSourceReadingChapter>{};
    final ambiguous = <(String, String)>{};
    for (final chapter in this.chapters) {
      final tid = chapter.sourceTid.trim();
      final pid = chapter.sourcePid?.trim() ?? '';
      if (tid.isEmpty || pid.isEmpty || chapter.episodeId.trim().isEmpty) {
        continue;
      }
      final key = (tid, pid);
      final previous = bySource[key];
      if (previous != null && previous.episodeId != chapter.episodeId) {
        ambiguous.add(key);
      } else {
        bySource[key] = chapter;
      }
    }
    for (final key in ambiguous) {
      bySource.remove(key);
    }
    _bySource = Map.unmodifiable(bySource);
  }

  final String novelId;
  final List<NovelSourceReadingChapter> chapters;
  final String? initialEpisodeId;
  final NovelReadingSessionEntry entry;
  late final Map<(String, String), NovelSourceReadingChapter> _bySource;

  NovelSourceReadingChapter? chapterForSource(String tid, String pid) =>
      _bySource[(tid.trim(), pid.trim())];

  NovelSourceReadingChapter? get initialChapter {
    final episodeId = initialEpisodeId;
    if (episodeId == null) return null;
    for (final chapter in _bySource.values) {
      if (chapter.episodeId == episodeId) return chapter;
    }
    return null;
  }
}

final class NovelSourceReadingChapter {
  const NovelSourceReadingChapter({
    required this.episodeId,
    required this.sourceTid,
    required this.sourcePid,
  });

  final String episodeId;
  final String sourceTid;
  final String? sourcePid;
}
