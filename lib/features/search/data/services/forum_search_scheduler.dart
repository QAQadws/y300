import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/search/data/services/forum_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/services/search_rate_limiter.dart';

class ForumSearchSchedulerSnapshot {
  const ForumSearchSchedulerSnapshot({
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

  static const empty = ForumSearchSchedulerSnapshot(
    pendingCount: 0,
    running: false,
  );
}

abstract class ForumSearchQueueStateReader {
  ValueListenable<ForumSearchSchedulerSnapshot> get snapshot;
}

class _ForumSearchJob {
  const _ForumSearchJob({
    required this.id,
    required this.keyword,
  });

  final int id;
  final String keyword;
}

/// Serializes real forum search requests behind one cadence.
///
/// `DiscuzSearchService` still owns Discuz-specific HTTP/parsing details; this
/// scheduler owns only timing and queue observation.  Callers that need raw
/// network access can depend on `rawDiscuzSearchServiceProvider` explicitly.
class ForumSearchScheduler implements ForumSearchService, ForumSearchQueueStateReader {
  ForumSearchScheduler({
    required ForumSearchService rawService,
    this.interval = SearchRateLimiter.defaultCooldown,
    DateTime Function()? nowProvider,
    Future<void> Function(Duration duration)? delay,
  })  : _rawService = rawService,
        _nowProvider = nowProvider ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  static const Duration defaultInterval = SearchRateLimiter.defaultCooldown;

  final ForumSearchService _rawService;
  final Duration interval;
  final DateTime Function() _nowProvider;
  final Future<void> Function(Duration duration) _delay;
  final ValueNotifier<ForumSearchSchedulerSnapshot> _snapshot =
      ValueNotifier<ForumSearchSchedulerSnapshot>(
    ForumSearchSchedulerSnapshot.empty,
  );

  Future<void> _tail = Future<void>.value();
  DateTime? _lastStartedAt;
  int _nextJobId = 0;
  bool _running = false;
  bool _disposed = false;
  final List<_ForumSearchJob> _jobs = <_ForumSearchJob>[];

  @override
  ValueListenable<ForumSearchSchedulerSnapshot> get snapshot => _snapshot;

  void dispose() {
    _disposed = true;
    _snapshot.dispose();
  }

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty || !enforceRateLimit) {
      return _rawService.searchForum(
        keyword: keyword,
        context: context,
        enforceRateLimit: enforceRateLimit,
      );
    }

    final job = _ForumSearchJob(id: _nextJobId++, keyword: trimmed);
    _jobs.add(job);
    _publishSnapshot();

    final previousTail = _tail;
    final scheduled = previousTail.then((_) async {
      _running = true;
      _publishSnapshot();
      try {
        await _waitForCadence();
        _lastStartedAt = _nowProvider();
        return await _rawService.searchForum(
          keyword: keyword,
          context: context,
          // The scheduler is now the single timing gate; the raw service should
          // only perform the Discuz HTTP exchange for scheduled jobs.
          enforceRateLimit: false,
        );
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
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) {
    return _rawService.fetchNextPage(
      nextPageUrl: nextPageUrl,
      context: context,
    );
  }

  Future<void> _waitForCadence() async {
    final lastStartedAt = _lastStartedAt;
    if (lastStartedAt == null) {
      return;
    }
    final elapsed = _nowProvider().difference(lastStartedAt);
    if (elapsed >= interval) {
      return;
    }
    await _delay(interval - elapsed);
  }

  void _publishSnapshot() {
    if (_disposed) {
      return;
    }
    final count = _jobs.length;
    _snapshot.value = ForumSearchSchedulerSnapshot(
      pendingCount: count,
      running: _running,
      headKeyword: count == 0 ? null : _jobs.first.keyword,
      estimatedWait: Duration(milliseconds: interval.inMilliseconds * count),
    );
  }
}
