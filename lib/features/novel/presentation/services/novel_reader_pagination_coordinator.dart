import 'dart:async';

import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_page_breaker.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_incremental_pagination_planner.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cache.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

abstract interface class NovelReaderPaginationCoordinator {
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  });

  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  });

  bool isCached(NovelReaderPaginationKey key);

  void clear();

  /// Cancels active work without evicting reusable plan cache entries.
  void cancelPending();

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
  final Map<NovelReaderPaginationKey, NovelReaderPaginationCancellationToken>
  _cancellationTokens =
      <NovelReaderPaginationKey, NovelReaderPaginationCancellationToken>{};
  final Map<NovelReaderPaginationKey, _PaginationProgressFlight>
  _progressFlights = <NovelReaderPaginationKey, _PaginationProgressFlight>{};
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
    final cancellationToken = NovelReaderPaginationCancellationToken();
    _cancellationTokens[key] = cancellationToken;
    final future = _build(
      chapter: chapter,
      key: key,
      requestGeneration: requestGeneration,
      cancellationToken: cancellationToken,
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
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    if (chapter.episodeId != key.episodeId) {
      return Stream<NovelReaderPaginationProgress>.error(
        const NovelReaderPaginationException(
          code: 'episodeMismatch',
          message:
              'Prepared chapter and pagination key refer to different episodes.',
        ),
      );
    }
    final cached = cache.get(key);
    if (cached != null) {
      return Stream<NovelReaderPaginationProgress>.value(
        NovelReaderPaginationProgress(
          plan: cached,
          isComplete: true,
          processedAtomCount: cached.atomCount,
          totalAtomCount: cached.atomCount,
        ),
      );
    }
    final existing = _progressFlights[key];
    if (existing != null) {
      return existing.stream;
    }

    final breaker = _isolatedBreaker();
    if (breaker is! NovelReaderIncrementalPaginationPlanner) {
      return Stream<NovelReaderPaginationProgress>.fromFuture(
        paginate(chapter: chapter, key: key).then(
          (plan) => NovelReaderPaginationProgress(
            plan: plan,
            isComplete: true,
            processedAtomCount: plan.atomCount,
            totalAtomCount: plan.atomCount,
          ),
        ),
      );
    }

    final requestGeneration = _generation;
    final cancellationToken = NovelReaderPaginationCancellationToken();
    final flight = _PaginationProgressFlight();
    _progressFlights[key] = flight;
    _cancellationTokens[key] = cancellationToken;
    unawaited(
      _buildIncrementally(
        planner: breaker as NovelReaderIncrementalPaginationPlanner,
        chapter: chapter,
        key: key,
        requestGeneration: requestGeneration,
        cancellationToken: cancellationToken,
        flight: flight,
      ),
    );
    return flight.stream;
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => cache.contains(key);

  Future<NovelReaderPaginationPlan> _build({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required int requestGeneration,
    required NovelReaderPaginationCancellationToken cancellationToken,
  }) async {
    final breaker = _isolatedBreaker();
    late final NovelReaderPaginationPlan plan;
    final supportsCancellation = breaker is NovelReaderCancellablePageBreaker;
    if (supportsCancellation) {
      final cancellableBreaker = breaker as NovelReaderCancellablePageBreaker;
      plan = await cancellableBreaker.paginateCancellable(
        chapter,
        key,
        cancellationToken,
      );
    } else {
      plan = await breaker.paginate(chapter, key);
    }
    if (supportsCancellation) {
      cancellationToken.throwIfCancelled();
    }
    if (requestGeneration != _generation) {
      throw const NovelReaderPaginationException(
        code: 'staleRequest',
        message: 'A newer pagination generation superseded this result.',
      );
    }
    cache.put(plan);
    return plan;
  }

  NovelReaderPageBreaker _isolatedBreaker() {
    return _pageBreaker is NovelReaderIsolatedPageBreakerFactory
        ? (_pageBreaker as NovelReaderIsolatedPageBreakerFactory)
              .createIsolated()
        : _pageBreaker;
  }

  Future<void> _buildIncrementally({
    required NovelReaderIncrementalPaginationPlanner planner,
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
    required int requestGeneration,
    required NovelReaderPaginationCancellationToken cancellationToken,
    required _PaginationProgressFlight flight,
  }) async {
    NovelReaderPaginationProgress? completed;
    try {
      await for (final progress in planner.planIncrementally(
        chapter: chapter,
        key: key,
        cancellationToken: cancellationToken,
      )) {
        cancellationToken.throwIfCancelled();
        if (requestGeneration != _generation) {
          throw const NovelReaderPaginationException(
            code: 'staleRequest',
            message: 'A newer pagination generation superseded this result.',
          );
        }
        flight.add(progress);
        if (progress.isComplete) {
          completed = progress;
        }
      }
      if (completed == null) {
        throw const NovelReaderPaginationException(
          code: 'incompletePaginationStream',
          message: 'Incremental pagination ended without a complete plan.',
        );
      }
      cache.put(completed.plan);
      flight.close();
    } catch (error, stackTrace) {
      flight.addError(error, stackTrace);
      flight.close();
    } finally {
      if (identical(_progressFlights[key], flight)) {
        _progressFlights.remove(key);
      }
      if (identical(_cancellationTokens[key], cancellationToken)) {
        _cancellationTokens.remove(key);
      }
    }
  }

  void _removeInFlight(
    NovelReaderPaginationKey key,
    Future<NovelReaderPaginationPlan> future,
  ) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
      _cancellationTokens.remove(key);
    }
  }

  @override
  void clear() {
    cancelPending();
    cache.clear();
  }

  @override
  void cancelPending() {
    _generation += 1;
    for (final token in _cancellationTokens.values) {
      token.cancel();
    }
    _cancellationTokens.clear();
    _inFlight.clear();
    for (final flight in _progressFlights.values) {
      flight.cancel();
    }
    _progressFlights.clear();
  }

  @override
  void clearEpisode(String episodeId) {
    _generation += 1;
    for (final entry in _cancellationTokens.entries) {
      if (entry.key.episodeId == episodeId) {
        entry.value.cancel();
      }
    }
    _cancellationTokens.removeWhere((key, _) => key.episodeId == episodeId);
    _inFlight.removeWhere((key, _) => key.episodeId == episodeId);
    for (final entry in _progressFlights.entries.toList(growable: false)) {
      if (entry.key.episodeId == episodeId) {
        entry.value.cancel();
        _progressFlights.remove(entry.key);
      }
    }
    cache.evictEpisode(episodeId);
  }
}

final class _PaginationProgressFlight {
  final Set<MultiStreamController<NovelReaderPaginationProgress>> _listeners =
      <MultiStreamController<NovelReaderPaginationProgress>>{};
  NovelReaderPaginationProgress? _latest;
  Object? _error;
  StackTrace? _stackTrace;
  bool _closed = false;

  late final Stream<NovelReaderPaginationProgress> stream =
      Stream<NovelReaderPaginationProgress>.multi((controller) {
        final latest = _latest;
        if (latest != null) {
          controller.add(latest);
        }
        if (_error case final error?) {
          controller.addError(error, _stackTrace ?? StackTrace.current);
        }
        if (_closed) {
          controller.close();
          return;
        }
        _listeners.add(controller);
        controller.onCancel = () {
          _listeners.remove(controller);
        };
      });

  void add(NovelReaderPaginationProgress progress) {
    if (_closed) {
      return;
    }
    _latest = progress;
    for (final listener in _listeners.toList(growable: false)) {
      listener.add(progress);
    }
  }

  void addError(Object error, StackTrace stackTrace) {
    if (_closed) {
      return;
    }
    _error = error;
    _stackTrace = stackTrace;
    for (final listener in _listeners.toList(growable: false)) {
      listener.addError(error, stackTrace);
    }
  }

  void cancel() {
    addError(
      const NovelReaderPaginationException(
        code: 'paginationCancelled',
        message: 'Pagination was cancelled by a newer layout request.',
      ),
      StackTrace.current,
    );
    close();
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final listener in _listeners.toList(growable: false)) {
      listener.close();
    }
    _listeners.clear();
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
