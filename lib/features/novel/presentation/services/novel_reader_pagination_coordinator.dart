import 'dart:async';

import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

abstract interface class NovelReaderPaginationCoordinator {
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  });

  bool isCached(NovelReaderPaginationKey key);

  void clear();

  void clearEpisode(String episodeId);
}

final class DefaultNovelReaderPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  DefaultNovelReaderPaginationCoordinator({
    required NovelReaderPageBreaker pageBreaker,
    NovelReaderPaginationCache? cache,
  }) : _pageBreaker = pageBreaker,
       cache = cache ?? NovelReaderPaginationCache();

  final NovelReaderPageBreaker _pageBreaker;
  final NovelReaderPaginationCache cache;
  final Map<NovelReaderPaginationKey, Future<NovelReaderPaginationPlan>>
  _inFlight = <NovelReaderPaginationKey, Future<NovelReaderPaginationPlan>>{};
  int _generation = 0;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    if (chapter.episodeId != key.episodeId) {
      return Future<NovelReaderPaginationPlan>.error(
        const NovelReaderPaginationException(
          code: 'episodeMismatch',
          message:
              'Prepared chapter and pagination key refer to different episodes.',
        ),
      );
    }
    final cached = cache.get(key);
    if (cached != null) {
      return Future<NovelReaderPaginationPlan>.value(cached);
    }

    final current = _inFlight[key];
    if (current != null) {
      return current;
    }

    final requestGeneration = _generation;
    final future = _build(
      chapter: chapter,
      key: key,
      requestGeneration: requestGeneration,
    );
    _inFlight[key] = future;
    unawaited(
      future.then<void>(
        (_) => _removeInFlight(key, future),
        onError: (Object error, StackTrace stack) =>
            _removeInFlight(key, future),
      ),
    );
    return future;
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => cache.contains(key);

  Future<NovelReaderPaginationPlan> _build({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required int requestGeneration,
  }) async {
    final plan = await _pageBreaker.paginate(chapter, key);
    if (requestGeneration != _generation) {
      throw const NovelReaderPaginationException(
        code: 'staleRequest',
        message: 'A newer pagination generation superseded this result.',
      );
    }
    cache.put(plan);
    return plan;
  }

  void _removeInFlight(
    NovelReaderPaginationKey key,
    Future<NovelReaderPaginationPlan> future,
  ) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }

  @override
  void clear() {
    _generation += 1;
    _inFlight.clear();
    cache.clear();
  }

  @override
  void clearEpisode(String episodeId) {
    _generation += 1;
    _inFlight.removeWhere((key, _) => key.episodeId == episodeId);
    cache.evictEpisode(episodeId);
  }
}

/// A small deterministic breaker useful for dependency injection in tests and
/// for non-widget callers that already have measured candidate heights.
final class NovelReaderEstimatedPaginationMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  const NovelReaderEstimatedPaginationMeasureAdapter({
    this.characterHeight = 1,
  });

  final double characterHeight;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    final count = request.html.runes.length;
    return NovelReaderPaginationMeasureResult(height: count * characterHeight);
  }
}
