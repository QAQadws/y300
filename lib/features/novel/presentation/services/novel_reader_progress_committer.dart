import 'dart:async';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

abstract interface class NovelReaderProgressCommitter {
  void schedule(NovelReaderProgressSnapshot snapshot);
  Future<void> flush(NovelReaderProgressSnapshot snapshot);
  void cancel();
}

/// Scoped authority keeps older consumers and test ports compatible.
abstract interface class ScopedNovelReaderProgressCommitter {
  void scheduleScoped(
    NovelReaderProgressSnapshot snapshot, {
    required Object scope,
    required bool Function() canCommit,
    void Function()? onCommitted,
  });
  Future<bool> flushScoped(
    NovelReaderProgressSnapshot snapshot, {
    required Object scope,
    required bool Function() canCommit,
    void Function()? onCommitted,
  });
}

class DefaultNovelReaderProgressCommitter
    implements
        NovelReaderProgressCommitter,
        ScopedNovelReaderProgressCommitter {
  DefaultNovelReaderProgressCommitter({
    required NovelRepository repository,
    NovelReadingStateRepository? readingStateRepository,
    this.debounceDuration = const Duration(milliseconds: 200),
  }) : _repository = repository,
       _readingStateRepository =
           readingStateRepository ??
           (repository is NovelReadingStateRepository
               ? repository as NovelReadingStateRepository
               : null);

  final NovelRepository _repository;
  final NovelReadingStateRepository? _readingStateRepository;
  final Duration debounceDuration;
  Timer? _debounceTimer;
  _PendingProgress? _pending;
  _PendingProgress? _lastCommitted;
  Future<void> _inFlight = Future<void>.value();
  int _generation = 0;

  @override
  void schedule(NovelReaderProgressSnapshot snapshot) =>
      scheduleScoped(snapshot, scope: this, canCommit: () => true);

  @override
  void scheduleScoped(
    NovelReaderProgressSnapshot snapshot, {
    required Object scope,
    required bool Function() canCommit,
    void Function()? onCommitted,
  }) {
    final pending = _pending = _PendingProgress(
      snapshot,
      scope,
      canCommit,
      _generation,
      onCommitted,
    );
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      _debounceTimer = null;
      if (identical(_pending, pending)) {
        unawaited(_commit(pending).catchError((Object _) => false));
      }
    });
  }

  @override
  Future<void> flush(NovelReaderProgressSnapshot snapshot) async {
    await flushScoped(snapshot, scope: this, canCommit: () => true);
  }

  @override
  Future<bool> flushScoped(
    NovelReaderProgressSnapshot snapshot, {
    required Object scope,
    required bool Function() canCommit,
    void Function()? onCommitted,
  }) {
    final pending = _pending = _PendingProgress(
      snapshot,
      scope,
      canCommit,
      _generation,
      onCommitted,
    );
    _debounceTimer?.cancel();
    _debounceTimer = null;
    return _commit(pending);
  }

  @override
  void cancel() {
    _generation++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = null;
  }

  Future<bool> _commit(_PendingProgress pending) async {
    var applied = false;
    bool eligible() => pending.generation == _generation && pending.canCommit();
    final work = _inFlight.catchError((Object _) {}).then((_) async {
      if (!eligible()) return;
      if (_lastCommitted?.snapshot == pending.snapshot &&
          _lastCommitted?.scope == pending.scope &&
          _lastCommitted?.generation == pending.generation) {
        applied = true;
        return;
      }
      final snapshot = pending.snapshot;
      final repository = _readingStateRepository;
      if (repository != null) {
        applied = await repository.commitProgress(
          progress: readingProgressFromSnapshot(snapshot),
          canCommit: eligible,
        );
      } else {
        await _repository.saveReadingProgress(
          novelId: snapshot.novelId,
          episodeId: snapshot.episodeId,
          scrollOffset: snapshot.scrollOffset,
          flowMode: snapshot.flowMode,
          pageIndex: snapshot.pageIndex,
          pageCount: snapshot.pageCount,
          anchorNodeId: snapshot.anchorNodeId,
          anchorTextOffset: snapshot.anchorTextOffset,
          anchorFormatVersion: snapshot.anchorFormatVersion,
          anchorTextIdentity: snapshot.anchorTextIdentity,
          paginationKey: snapshot.paginationKey,
          progressPercent: snapshot.progressPercent,
          isProgressPercentValid: snapshot.isProgressPercentValid,
        );
        applied = true;
      }
      if (applied && eligible()) {
        _lastCommitted = pending;
        pending.onCommitted?.call();
      }
      if (identical(_pending, pending)) _pending = null;
    });
    _inFlight = work;
    await work;
    return applied;
  }
}

NovelReadingProgress readingProgressFromSnapshot(
  NovelReaderProgressSnapshot snapshot,
) => NovelReadingProgress(
  novelId: snapshot.novelId,
  episodeId: snapshot.episodeId,
  scrollOffset: snapshot.scrollOffset,
  updatedAt: DateTime.now(),
  flowMode: snapshot.flowMode,
  pageIndex: snapshot.pageIndex,
  pageCount: snapshot.pageCount,
  anchorNodeId: snapshot.anchorNodeId,
  anchorTextOffset: snapshot.anchorTextOffset,
  anchorFormatVersion: snapshot.anchorFormatVersion,
  anchorTextIdentity: snapshot.anchorTextIdentity,
  paginationKey: snapshot.paginationKey,
  progressPercent: snapshot.progressPercent,
  isProgressPercentValid: snapshot.isProgressPercentValid,
  percentBasis: snapshot.percentBasis,
);

final class _PendingProgress {
  const _PendingProgress(
    this.snapshot,
    this.scope,
    this.canCommit,
    this.generation,
    this.onCommitted,
  );
  final NovelReaderProgressSnapshot snapshot;
  final Object scope;
  final bool Function() canCommit;
  final int generation;
  final void Function()? onCommitted;
}
