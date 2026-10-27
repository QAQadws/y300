import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/repositories/favorite_parse_job_repository.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';

class DefaultFavoriteParseCoordinator implements FavoriteParseService {
  DefaultFavoriteParseCoordinator({
    required this.accountId,
    required this.repository,
    required this.executor,
    required this.isOwnerCurrent,
  });

  final String accountId;
  final FavoriteParseJobRepository repository;
  final FavoriteThreadParseExecutor executor;
  final bool Function() isOwnerCurrent;
  Future<void>? _draining;
  Future<void>? _recovery;
  bool _closed = false;
  bool _wakeRequested = false;
  Completer<void>? _wake;
  final Set<Future<void>> _executing = {};
  final Set<String> _cancelled = {};

  bool get _valid => !_closed && isOwnerCurrent();
  Future<void> get settled => _draining ?? Future<void>.value();

  Future<void> _ensureRecovered() {
    final existing = _recovery;
    if (existing != null) return existing;
    late final Future<void> future;
    future = repository.recover(accountId).catchError((
      Object error,
      StackTrace stack,
    ) {
      if (identical(_recovery, future)) _recovery = null;
      Error.throwWithStackTrace(error, stack);
    });
    _recovery = future;
    return future;
  }

  @override
  Future<FavoriteParseAdmission> requestThreads(Set<String> tids) async {
    if (!_valid) throw StateError('favorite_parse_owner_changed');
    await _ensureRecovered();
    var added = 0, existing = 0, rejected = 0;
    for (final tid in tids.map((e) => e.trim()).toSet()) {
      if (tid.isEmpty) {
        rejected++;
        continue;
      }
      try {
        final fresh = await repository.enqueue(
          accountId,
          FavoriteParseTarget(tid: tid),
          isCurrent: () => _valid,
        );
        _cancelled.remove(tid);
        fresh ? added++ : existing++;
      } catch (_) {
        rejected++;
      }
    }
    _kick();
    return FavoriteParseAdmission(
      enqueued: added,
      existing: existing,
      rejected: rejected,
    );
  }

  @override
  Future<void> requestConfirmed(
    ThreadFavoriteReceipt receipt, {
    String? title,
  }) async {
    if (!_valid) throw StateError('favorite_parse_owner_changed');
    if (receipt.targetState != FavoriteTargetState.favorited ||
        receipt.tid.trim().isEmpty) {
      throw ArgumentError('favorite_parse_confirmation_invalid');
    }
    await _ensureRecovered();
    await repository.enqueue(
      accountId,
      FavoriteParseTarget(
        tid: receipt.tid.trim(),
        confirmed: true,
        remoteFavoriteId: receipt.remoteFavoriteId,
        title: title,
      ),
      isCurrent: () => _valid,
    );
    _cancelled.remove(receipt.tid.trim());
    executor.noteMembershipChange(
      {receipt.tid.trim()},
      favorited: true,
      remoteFavoriteId: receipt.remoteFavoriteId,
    );
    _kick();
  }

  @override
  Future<void> resume() async {
    if (!_valid) return;
    await _ensureRecovered();
    _kick();
    await settled;
  }

  void _kick() {
    if (!_valid) return;
    _wakeRequested = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    if (_draining != null) return;
    _draining = _drain()
        .catchError((Object _) {
          // Durable queued/running rows remain available to a later resume.
          _recovery = null;
        })
        .whenComplete(() {
          _draining = null;
          if (_wakeRequested && _valid) _kick();
        });
  }

  Future<void> _drain() async {
    try {
      while (_valid) {
        _wakeRequested = false;
        while (_valid && _executing.length < 20) {
          final job = await repository.claim(accountId);
          if (job == null) break;
          late final Future<void> execution;
          execution = _runJob(job)
              .catchError((Object _) {
                _recovery = null;
              })
              .whenComplete(() {
                _executing.remove(execution);
                _wakeRequested = true;
                final wake = _wake;
                if (wake != null && !wake.isCompleted) wake.complete();
              });
          _executing.add(execution);
        }
        if (!_valid || (_executing.isEmpty && !_wakeRequested)) break;
        if (!_wakeRequested) {
          _wake = Completer<void>();
          await _wake!.future;
          _wake = null;
        }
      }
    } finally {
      await Future.wait(_executing.toList());
    }
  }

  Future<void> _runJob(FavoriteParseJob job) async {
    Future<bool> current() async {
      if (!_valid || _cancelled.contains(job.target.tid)) return false;
      final stored = await repository.isCurrent(job);
      return stored && _valid && !_cancelled.contains(job.target.tid);
    }

    if (!await current()) {
      return;
    }
    try {
      if (job.target.confirmed) {
        executor.noteMembershipChange(
          {job.target.tid},
          favorited: true,
          remoteFavoriteId: job.target.remoteFavoriteId,
          onlyIfUnknown: true,
        );
      }
      await executor.parseThread(job.target, isCurrent: current);
      if (await current()) await repository.finish(job);
    } catch (_) {
      if (await current()) {
        await repository.finish(job, errorCode: 'favorite_parse_failed');
      }
    }
  }

  @override
  Future<Set<String>> cancelThreads(Set<String> tids) async {
    if (!_valid) throw StateError('favorite_parse_owner_changed');
    executor.noteMembershipChange(tids, favorited: false);
    // The caller removes shelf entries after any already-started ingest has
    // settled. Do not retire an ingest halfway through its module writes: its
    // final binding is needed by the unfavorite use case for shelf cleanup.
    await executor.waitForPendingOperations();
    if (!_valid) throw StateError('favorite_parse_owner_changed');
    final current = tids.where(executor.isUnfavorited).toSet();
    _cancelled.addAll(current);
    await repository.cancel(accountId, current);
    return current;
  }

  void close() {
    _closed = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }
}
