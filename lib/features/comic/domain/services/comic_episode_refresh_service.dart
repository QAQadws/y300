import 'package:y300/features/comic/domain/models/comic_models.dart';

abstract class ComicEpisodeRefreshService {
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  );

  /// Runs the full refresh decision tree: catalog first, then search/current
  /// fallback when catalog misses.
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  );

  /// Runs only strategy 1. A miss intentionally returns an empty outcome so
  /// callers can enqueue search without spending a search request here.
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  );

  /// Runs strategy 2 and strategy 3 for callers that already decided catalog
  /// refresh should not run immediately, such as the future search queue.
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  );

  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid);
}

enum ComicEpisodeRefreshSource {
  catalog,
  search,
  currentOnly,
  empty,
}

class ComicEpisodeRefreshOutcome {
  const ComicEpisodeRefreshOutcome({
    required this.source,
    required this.links,
    this.usedSearch = false,
    this.catalogMatched = false,
  });

  final ComicEpisodeRefreshSource source;
  final List<ComicEpisodeLink> links;
  final bool usedSearch;
  final bool catalogMatched;

  bool get hasLinks => links.isNotEmpty;
}

class ComicEpisodeRefreshRequest {
  const ComicEpisodeRefreshRequest({
    required this.sourceTid,
    this.comicId,
    this.displayTitle,
    this.sourceTitle,
    this.customTitle,
    this.customSearchTitle,
  });

  final String? comicId;
  final String sourceTid;
  final String? displayTitle;
  final String? sourceTitle;
  final String? customTitle;
  final String? customSearchTitle;
}

class ThreadSeed {
  const ThreadSeed({required this.subject});

  final String subject;
}

typedef ThreadSeedFetcher = Future<ThreadSeed?> Function(String tid);
