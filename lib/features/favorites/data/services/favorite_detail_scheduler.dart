import 'dart:async';

import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/services/favorite_execution_queue.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';
import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';

class FavoriteDetailWork {
  FavoriteDetailWork({
    required this.target,
    required this.owner,
    required this.context,
    required this.isCurrent,
    this.foreground = false,
    this.forceRead = false,
    this.forceSearch = false,
    this.mergeComics = true,
    this.membershipRevision = 0,
    this.preloadedDetail,
  });
  final FavoriteParseTarget target;
  final Object? owner;
  final FavoriteSyncExecutionContext context;
  final Future<bool> Function() isCurrent;
  final bool foreground, forceRead, forceSearch, mergeComics;
  final int membershipRevision;
  final DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?
  preloadedDetail;

  bool covers(
    FavoriteDetailWork other, {
    bool readStarted = false,
    bool comicOptions = true,
  }) =>
      (!other.forceRead || forceRead || readStarted) &&
      (!comicOptions || !other.forceSearch || forceSearch) &&
      (!comicOptions || !other.mergeComics || mergeComics) &&
      membershipRevision >= other.membershipRevision &&
      (!other.target.confirmed ||
          (target.confirmed &&
              target.remoteFavoriteId == other.target.remoteFavoriteId));

  FavoriteDetailWork merge(FavoriteDetailWork other) => FavoriteDetailWork(
    target: other.target.confirmed ? other.target : target,
    owner: owner,
    context: other.foreground ? other.context : context,
    foreground: foreground || other.foreground,
    forceRead: forceRead || other.forceRead,
    forceSearch: forceSearch || other.forceSearch,
    mergeComics: mergeComics || other.mergeComics,
    membershipRevision: membershipRevision > other.membershipRevision
        ? membershipRevision
        : other.membershipRevision,
    preloadedDetail: other.preloadedDetail ?? preloadedDetail,
    isCurrent: () async => await isCurrent() || await other.isCurrent(),
  );

  FavoriteDetailWork withEligibility(Future<bool> Function() guard) =>
      FavoriteDetailWork(
        target: target,
        owner: owner,
        context: context,
        isCurrent: guard,
        foreground: foreground,
        forceRead: forceRead,
        forceSearch: forceSearch,
        mergeComics: mergeComics,
        membershipRevision: membershipRevision,
        preloadedDetail: preloadedDetail,
      );
}

/// Coalesces auto and foreground work. An in-flight requirement upgrade gets
/// one queued successor; no second request runs concurrently for the same TID.
class FavoriteDetailScheduler {
  FavoriteDetailScheduler(this.queue, this.execute, {this.resultCovers});
  final FavoriteExecutionQueue queue;
  final Future<bool> Function(FavoriteDetailWork, void Function()) execute;
  final Future<bool> Function(FavoriteDetailWork, FavoriteDetailWork, bool)?
  resultCovers;
  final Map<(Object?, String), _DetailEntry> _entries = {};

  Future<bool> request(FavoriteDetailWork work) {
    final key = (work.owner, work.target.tid);
    final old = _entries[key];
    if (old != null) {
      old.guards.add(work.isCurrent);
      if (!old.started) {
        old.work = old.work.merge(work);
      } else if (!old.work.covers(work, readStarted: old.readStarted)) {
        old.successor = (old.successor ?? old.work).merge(work);
      }
      return old.result.future;
    }
    final entry = _DetailEntry(work);
    _entries[key] = entry;
    _schedule(key, entry);
    return entry.result.future;
  }

  void _schedule((Object?, String) key, _DetailEntry entry) {
    unawaited(
      queue.run(
        () async {
          entry.started = true;
          entry.readStarted = false;
          bool? loaded;
          Object? failure;
          StackTrace? stack;
          try {
            loaded = await execute(
              entry.work.withEligibility(entry.isCurrent),
              () => entry.readStarted = true,
            );
          } catch (error, trace) {
            failure = error;
            stack = trace;
          }
          var successor = entry.successor;
          if (loaded == true && successor != null && resultCovers != null) {
            // Requests can arrive while readiness is checked. Recheck the
            // latest demand after the asynchronous coverage check as well.
            final candidate = successor;
            var covered = false;
            try {
              covered = await resultCovers!(
                entry.work,
                candidate,
                entry.readStarted,
              );
            } catch (_) {
              /* A failed readiness read cannot prove coverage. */
            }
            successor = covered && identical(candidate, entry.successor)
                ? null
                : entry.successor;
          }
          if (successor != null) {
            entry.work = successor;
            entry.successor = null;
            entry.started = false;
            _schedule(key, entry);
            return;
          }
          _entries.remove(key);
          if (failure != null) {
            entry.result.completeError(failure, stack);
          } else {
            entry.result.complete(loaded!);
          }
        },
        currentPriority: () => entry.work.foreground
            ? FavoriteWorkPriority.foreground
            : FavoriteWorkPriority.automatic,
      ),
    );
  }
}

class _DetailEntry {
  _DetailEntry(this.work) {
    guards.add(work.isCurrent);
  }
  final List<Future<bool> Function()> guards = [];
  Future<bool> isCurrent() async {
    for (var index = 0; index < guards.length; index++) {
      if (await guards[index]()) return true;
    }
    return false;
  }

  FavoriteDetailWork work;
  FavoriteDetailWork? successor;
  bool started = false;
  bool readStarted = false;
  final Completer<bool> result = Completer<bool>();
}
