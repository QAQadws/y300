import 'dart:async';

import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

abstract interface class NovelReaderProgressCommitter {
  void schedule(NovelReaderProgressSnapshot snapshot);

  Future<void> flush(NovelReaderProgressSnapshot snapshot);

  void cancel();
}

class DefaultNovelReaderProgressCommitter
    implements NovelReaderProgressCommitter {
  DefaultNovelReaderProgressCommitter({
    required NovelRepository repository,
    this.debounceDuration = const Duration(milliseconds: 200),
  }) : _repository = repository;

  final NovelRepository _repository;
  final Duration debounceDuration;
  Timer? _debounceTimer;
  NovelReaderProgressSnapshot? _pendingSnapshot;
  NovelReaderProgressSnapshot? _lastCommittedSnapshot;
  Future<void> _inFlightCommit = Future<void>.value();

  @override
  void schedule(NovelReaderProgressSnapshot snapshot) {
    _pendingSnapshot = snapshot;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      final pending = _pendingSnapshot;
      if (pending == null) {
        return;
      }
      unawaited(_commit(pending));
    });
  }

  @override
  Future<void> flush(NovelReaderProgressSnapshot snapshot) async {
    _pendingSnapshot = snapshot;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _commit(snapshot);
  }

  @override
  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingSnapshot = null;
  }

  Future<void> _commit(NovelReaderProgressSnapshot snapshot) async {
    if (_lastCommittedSnapshot == snapshot) {
      _pendingSnapshot = null;
      return;
    }
    _inFlightCommit = _inFlightCommit.catchError((_) {}).then((_) async {
      if (_lastCommittedSnapshot == snapshot) {
        _pendingSnapshot = null;
        return;
      }
      await _repository.saveReadingProgress(
        novelId: snapshot.novelId,
        episodeId: snapshot.episodeId,
        scrollOffset: snapshot.scrollOffset,
        flowMode: snapshot.flowMode,
        pageIndex: snapshot.pageIndex,
        pageCount: snapshot.pageCount,
        anchorNodeId: snapshot.anchorNodeId,
        anchorTextOffset: snapshot.anchorTextOffset,
        paginationKey: snapshot.paginationKey,
        progressPercent: snapshot.progressPercent,
      );
      _lastCommittedSnapshot = snapshot;
      if (_pendingSnapshot == snapshot) {
        _pendingSnapshot = null;
      }
    });
    await _inFlightCommit;
  }
}
