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
    do {
      _wakeRequested = false;
      while (_valid) {
        final job = await repository.claim(accountId);
        if (job == null) break;
        Future<bool> current() async {
          if (!_valid || _cancelled.contains(job.target.tid)) return false;
          final stored = await repository.isCurrent(job);
          return stored && _valid && !_cancelled.contains(job.target.tid);
        }

        if (!await current()) {
          if (!_valid) break;
          continue;
        }
        try {
          await executor.parseThread(job.target, isCurrent: current);
          if (await current()) await repository.finish(job);
        } catch (_) {
          if (await current()) {
            await repository.finish(job, errorCode: 'favorite_parse_failed');
          }
        }
      }
    } while (_wakeRequested && _valid);
  }

  @override
  Future<void> cancelThreads(Set<String> tids) async {
    if (!_valid) throw StateError('favorite_parse_owner_changed');
    // The caller removes shelf entries after any already-started ingest has
    // settled. Do not retire an ingest halfway through its module writes: its
    // final binding is needed by the unfavorite use case for shelf cleanup.
    await executor.waitForPendingOperations();
    if (!_valid) throw StateError('favorite_parse_owner_changed');
    _cancelled.addAll(tids);
    await repository.cancel(accountId, tids);
  }

  void close() {
    _closed = true;
  }
}
