import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/search/data/providers/forum_search_providers.dart';
import 'package:y300/features/search/data/services/search_rate_limiter.dart';

final class ForumSearchExecution {
  const ForumSearchExecution._({this.readResult, this.retryAfter});

  const ForumSearchExecution.read(
    DataReadResult<ForumSearchData, ForumSearchReadCapabilities> result,
  ) : this._(readResult: result);

  const ForumSearchExecution.rateLimited(Duration retryAfter)
    : this._(retryAfter: retryAfter);

  final DataReadResult<ForumSearchData, ForumSearchReadCapabilities>?
  readResult;
  final Duration? retryAfter;

  bool get isRateLimited => retryAfter != null;

  DataReadFailure<ForumSearchData, ForumSearchReadCapabilities>? get failure =>
      readResult?.failureOrNull;
}

abstract interface class ForumSearchCoordinator {
  Future<ForumSearchExecution> search(
    ForumSearchQuery query, {
    bool enforceRateLimit = true,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });

  Future<ForumSearchExecution> loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page,
  );
}

abstract interface class ForumSearchReadQueueStateReader {
  ValueListenable<ForumSearchReadSchedulerSnapshot> get snapshot;
}

final class ForumSearchReadSchedulerSnapshot {
  const ForumSearchReadSchedulerSnapshot({
    required this.pendingCount,
    required this.running,
    this.headKeyword,
    this.estimatedWait = Duration.zero,
  });

  final int pendingCount;
  final bool running;
  final String? headKeyword;
  final Duration estimatedWait;

  bool get active => running || pendingCount > 0;

  static const empty = ForumSearchReadSchedulerSnapshot(
    pendingCount: 0,
    running: false,
  );
}

final class ForumSearchReadScheduler
    implements ForumSearchCoordinator, ForumSearchReadQueueStateReader {
  ForumSearchReadScheduler({
    required ForumSearchRepository repository,
    required SearchRateLimiter rateLimiter,
    this.interval = SearchRateLimiter.defaultCooldown,
    DateTime Function()? nowProvider,
    Future<void> Function(Duration duration)? delay,
  }) : _repository = repository,
       _rateLimiter = rateLimiter,
       _nowProvider = nowProvider ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _snapshot = ValueNotifier<ForumSearchReadSchedulerSnapshot>(
         ForumSearchReadSchedulerSnapshot.empty,
       );

  final ForumSearchRepository _repository;
  final SearchRateLimiter _rateLimiter;
  final Duration interval;
  final DateTime Function() _nowProvider;
  final Future<void> Function(Duration duration) _delay;
  final ValueNotifier<ForumSearchReadSchedulerSnapshot> _snapshot;

  Future<void> _tail = Future<void>.value();
  DateTime? _lastStartedAt;
  int _nextJobId = 0;
  bool _running = false;
  bool _disposed = false;
  final List<_SearchJob> _jobs = <_SearchJob>[];

  @override
  ValueListenable<ForumSearchReadSchedulerSnapshot> get snapshot => _snapshot;

  @override
  Future<ForumSearchExecution> search(
    ForumSearchQuery query, {
    bool enforceRateLimit = true,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final normalized = query.normalized();
    if (enforceRateLimit) {
      final limit = await _rateLimiter.check();
      if (!limit.isAllowed) {
        return ForumSearchExecution.rateLimited(limit.retryAfter);
      }
    }
    final job = _SearchJob(id: _nextJobId++, keyword: normalized.keyword);
    _jobs.add(job);
    _publishSnapshot();
    final previousTail = _tail;
    final scheduled = previousTail.then((_) async {
      _running = true;
      _publishSnapshot();
      try {
        await _waitForCadence();
        _lastStartedAt = _nowProvider();
        final result = await _repository.load(
          normalized,
          cachePolicy: cachePolicy,
        );
        if (result.isSuccess && enforceRateLimit) {
          await _rateLimiter.markTriggered();
        }
        return ForumSearchExecution.read(result);
      } finally {
        _running = false;
        _jobs.removeWhere((candidate) => candidate.id == job.id);
        _publishSnapshot();
      }
    });
    _tail = scheduled.then<void>((_) {}, onError: (_) {});
    return scheduled;
  }

  @override
  Future<ForumSearchExecution> loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page,
  ) async {
    final result = await _repository.loadNextPage(
      query.normalized(),
      page,
      cachePolicy: CacheLoadPolicy.networkFirst,
    );
    return ForumSearchExecution.read(result);
  }

  Future<void> _waitForCadence() async {
    final lastStartedAt = _lastStartedAt;
    if (lastStartedAt == null) {
      return;
    }
    final elapsed = _nowProvider().difference(lastStartedAt);
    if (elapsed < interval) {
      await _delay(interval - elapsed);
    }
  }

  void _publishSnapshot() {
    if (_disposed) {
      return;
    }
    final count = _jobs.length;
    _snapshot.value = ForumSearchReadSchedulerSnapshot(
      pendingCount: count,
      running: _running,
      headKeyword: count == 0 ? null : _jobs.first.keyword,
      estimatedWait: Duration(milliseconds: interval.inMilliseconds * count),
    );
  }

  void dispose() {
    _disposed = true;
    _snapshot.dispose();
  }
}

final class _SearchJob {
  const _SearchJob({required this.id, required this.keyword});

  final int id;
  final String keyword;
}

final searchRateLimiterProvider = Provider<SearchRateLimiter>((ref) {
  return SearchRateLimiter();
});

final forumSearchCoordinatorProvider = Provider<ForumSearchCoordinator>((ref) {
  final scheduler = ForumSearchReadScheduler(
    repository: ref.read(forumSearchRepositoryProvider),
    rateLimiter: ref.read(searchRateLimiterProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

final forumSearchQueueStateReaderProvider =
    Provider<ForumSearchReadQueueStateReader?>((ref) {
      final coordinator = ref.watch(forumSearchCoordinatorProvider);
      return coordinator is ForumSearchReadQueueStateReader
          ? coordinator as ForumSearchReadQueueStateReader
          : null;
    });
