import 'dart:developer' as developer;

/// Source of a reader progress event.
///
/// Keeping the source explicit makes Phase 0 logs useful when debugging
/// whether progress came from vertical scrolling, page settling, slider jumps,
/// or reader exit persistence.
enum ComicReaderProgressSource {
  initialVisible,
  scroll,
  pageSettled,
  jump,
  exit,
}

/// Lightweight event logger for reader lifecycle and progress events.
///
/// This intentionally stays tiny and dependency-free.  A later telemetry layer
/// can replace this class without changing reader state policy.
class ComicReaderEventLogger {
  const ComicReaderEventLogger();

  void log({
    required String event,
    required String comicId,
    required String episodeId,
    ComicReaderProgressSource? source,
    int? pageIndex,
    int? totalPages,
    double? scrollOffset,
    int? elapsedMs,
    int? sinceOpenMs,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    developer.log(
      [
        'event=$event',
        'comicId=$comicId',
        'episodeId=$episodeId',
        if (source != null) 'source=${source.name}',
        if (pageIndex != null) 'pageIndex=$pageIndex',
        if (totalPages != null) 'totalPages=$totalPages',
        if (scrollOffset != null) 'scrollOffset=${scrollOffset.toStringAsFixed(1)}',
        if (elapsedMs != null) 'elapsedMs=$elapsedMs',
        if (sinceOpenMs != null) 'sinceOpenMs=$sinceOpenMs',
        for (final entry in extra.entries)
          if (entry.value != null) '${entry.key}=${entry.value}',
      ].join(' '),
      name: 'ComicReader',
    );
  }
}
