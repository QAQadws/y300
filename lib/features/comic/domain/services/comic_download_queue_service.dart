import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/repositories/comic_download_queue_repository.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_execution.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

final class ComicDownloadQueueService implements ComicDownloadQueue {
  ComicDownloadQueueService({
    required ComicDownloadQueueRepository queueRepository,
    required ComicDownloadService downloadService,
    required LibraryStateRepository libraryStateRepository,
    required LibraryShelfRefreshBus shelfRefreshBus,
    ValueNotifier<ComicDownloadQueueSnapshot>? snapshotNotifier,
    DateTime Function()? nowProvider,
  }) : _queueRepository = queueRepository,
       _downloadService = downloadService,
       _downloadAvailabilityChecker =
           downloadService is ComicDownloadAvailabilityChecker
           ? downloadService as ComicDownloadAvailabilityChecker
           : null,
       _libraryStateRepository = libraryStateRepository,
       _shelfRefreshBus = shelfRefreshBus,
       _nowProvider = nowProvider ?? DateTime.now,
       _snapshot =
           snapshotNotifier ??
           ValueNotifier<ComicDownloadQueueSnapshot>(
             ComicDownloadQueueSnapshot.empty,
           ),
       _ownsSnapshotNotifier = snapshotNotifier == null;

  final ComicDownloadQueueRepository _queueRepository;
  final ComicDownloadService _downloadService;
  final ComicDownloadAvailabilityChecker? _downloadAvailabilityChecker;
  final LibraryStateRepository _libraryStateRepository;
  final LibraryShelfRefreshBus _shelfRefreshBus;
  final DateTime Function() _nowProvider;
  final ValueNotifier<ComicDownloadQueueSnapshot> _snapshot;
  final bool _ownsSnapshotNotifier;
  final Map<int, ComicDownloadCancellationToken> _tokens =
      <int, ComicDownloadCancellationToken>{};
  final Map<int, ComicDownloadQueueEntry> _runningEntries =
      <int, ComicDownloadQueueEntry>{};

  bool _started = false;
  bool _disposed = false;
  bool _processing = false;
  bool _pumpRequested = false;
  Future<void>? _startFuture;
  Future<void>? _pumpFuture;

  @override
  ValueListenable<ComicDownloadQueueSnapshot> get snapshot => _snapshot;

  @override
  Future<ComicDownloadEnqueueResult> enqueueTargets(
    Iterable<ComicDownloadTarget> targets,
  ) async {
    final normalized = <ComicDownloadTarget>[];
    var requested = 0;
    var skippedDownloaded = 0;
    final seen = <String>{};
    for (final target in targets) {
      final comicId = target.comicId.trim();
      final episodeId = target.episodeId.trim();
      if (comicId.isEmpty || episodeId.isEmpty) {
        continue;
      }
      requested += 1;
      final identity = '$comicId\n$episodeId';
      if (!seen.add(identity)) {
        continue;
      }
      final state = await _libraryStateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: episodeId,
      );
      if (state?.isDownloaded == true) {
        final checker = _downloadAvailabilityChecker;
        final hasValidDownload =
            checker == null ||
            await checker.hasValidEpisodeDownload(
              comicId: comicId,
              episodeId: episodeId,
            );
        if (hasValidDownload) {
          skippedDownloaded += 1;
          continue;
        }
        await _libraryStateRepository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.comic,
          episodeId: episodeId,
          workId: comicId,
          isDownloaded: false,
          downloadedAt: null,
        );
      }
      normalized.add(
        ComicDownloadTarget(
          comicId: comicId,
          episodeId: episodeId,
          comicTitle: _displayTitle(target.comicTitle, comicId),
          episodeTitle: _displayTitle(target.episodeTitle, episodeId),
        ),
      );
    }

    final result = await _queueRepository.enqueueTargets(
      normalized,
      now: _nowProvider(),
    );
    await _refreshSnapshot();
    if (!_started) {
      await start();
    } else {
      _schedulePump();
    }
    return ComicDownloadEnqueueResult(
      requestedCount: requested,
      enqueuedCount: result.enqueuedCount,
      deduplicatedCount: result.deduplicatedCount,
      skippedDownloadedCount: skippedDownloaded,
    );
  }

  @override
  Future<void> start() async {
    if (_disposed) {
      return;
    }
    if (_started) {
      _schedulePump();
      return;
    }
    final activeStart = _startFuture;
    if (activeStart != null) {
      await activeStart;
      _schedulePump();
      return;
    }

    late final Future<void> startFuture;
    startFuture = _initialize().whenComplete(() {
      if (identical(_startFuture, startFuture)) {
        _startFuture = null;
      }
    });
    _startFuture = startFuture;
    await startFuture;
    _schedulePump();
  }

  Future<void> _initialize() async {
    await _queueRepository.recoverInterrupted(now: _nowProvider());
    await _refreshSnapshot();
    _started = true;
  }

  @override
  Future<void> cancel(int taskId) async {
    _tokens[taskId]?.cancel();
    await _queueRepository.requestCancel(id: taskId, now: _nowProvider());
    final deleted = await _queueRepository.deleteIfNotRunning(taskId);
    if (!deleted) {
      // The worker may have claimed a pending row while cancellation was
      // crossing the database boundary. Persist and signal cancellation once
      // more after the conditional delete closes that race.
      await _queueRepository.requestCancel(id: taskId, now: _nowProvider());
      _tokens[taskId]?.cancel();
    }
    await _refreshSnapshot();
  }

  @override
  Future<void> retry(int taskId) async {
    await _queueRepository.retry(id: taskId, now: _nowProvider());
    await _refreshSnapshot();
    if (_started) {
      _schedulePump();
    } else {
      await start();
    }
  }

  @override
  Future<void> remove(int taskId) async {
    await cancel(taskId);
  }

  @override
  Future<void> cancelEpisode(String comicId, String episodeId) async {
    final matching = <int, ComicDownloadQueueEntry>{
      for (final entry in _snapshot.value.entries)
        if (entry.comicId == comicId && entry.episodeId == episodeId)
          entry.id: entry,
      for (final entry in _runningEntries.values)
        if (entry.comicId == comicId && entry.episodeId == episodeId)
          entry.id: entry,
    };
    for (final entry in matching.values) {
      await cancel(entry.id);
    }
    await _queueRepository.deleteByEpisode(comicId, episodeId);
    await _refreshSnapshot();
  }

  @override
  Future<void> cancelComic(String comicId) async {
    final matching = <int, ComicDownloadQueueEntry>{
      for (final entry in _snapshot.value.entries)
        if (entry.comicId == comicId) entry.id: entry,
      for (final entry in _runningEntries.values)
        if (entry.comicId == comicId) entry.id: entry,
    };
    for (final entry in matching.values) {
      await cancel(entry.id);
    }
    await _queueRepository.deleteByComic(comicId);
    await _refreshSnapshot();
  }

  @visibleForTesting
  Future<void> drainForTest() async {
    while (!_disposed) {
      final future = _pumpFuture;
      if (future != null) {
        await future;
      } else {
        await _pump();
      }
      if (_pumpFuture == null && !_processing) {
        return;
      }
    }
  }

  void dispose() {
    _disposed = true;
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    _runningEntries.clear();
    if (_ownsSnapshotNotifier) {
      _snapshot.dispose();
    }
  }

  void _schedulePump() {
    if (_disposed) {
      return;
    }
    if (_processing || _pumpFuture != null) {
      _pumpRequested = true;
      return;
    }
    _pumpRequested = false;
    late final Future<void> scheduled;
    scheduled = Future<void>.microtask(_pump).whenComplete(() {
      if (identical(_pumpFuture, scheduled)) {
        _pumpFuture = null;
      }
      if (_pumpRequested && !_disposed) {
        _schedulePump();
      }
    });
    _pumpFuture = scheduled;
  }

  Future<void> _pump() async {
    if (_disposed || _processing) {
      return;
    }
    _processing = true;
    try {
      while (!_disposed) {
        final entry = await _queueRepository.claimNext(now: _nowProvider());
        if (entry == null) {
          return;
        }
        final token = ComicDownloadCancellationToken();
        _tokens[entry.id] = token;
        _runningEntries[entry.id] = entry;
        final persisted = await _queueRepository.getById(entry.id);
        if (persisted == null ||
            persisted.status == ComicDownloadQueueStatus.cancelRequested) {
          token.cancel();
        }
        await _refreshSnapshot();
        await _runEntry(entry, token);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _runEntry(
    ComicDownloadQueueEntry entry,
    ComicDownloadCancellationToken token,
  ) async {
    final observer = _QueueProgressObserver(
      onProgress: (completed, total) async {
        await _queueRepository.updateProgress(
          id: entry.id,
          completedImages: completed,
          totalImages: total,
          now: _nowProvider(),
        );
        await _refreshSnapshot();
      },
    );
    try {
      await _downloadService.downloadEpisode(
        comicId: entry.comicId,
        episodeId: entry.episodeId,
        observer: observer,
        cancellationToken: token,
      );
      token.throwIfCancellationRequested();
      await _libraryStateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: entry.episodeId,
        workId: entry.comicId,
        isDownloaded: true,
        downloadedAt: _nowProvider(),
      );
      await _queueRepository.delete(entry.id);
      _shelfRefreshBus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        reason: 'comic_download_completed',
        source: LibraryMutationSource.bulkDownload,
        workId: entry.comicId,
        payload: <String, Object?>{'episodeId': entry.episodeId},
      );
    } on ComicDownloadCanceledException {
      await _queueRepository.delete(entry.id);
    } catch (error) {
      await _queueRepository.markFailed(
        id: entry.id,
        error: _stableFailureCode(error).storageValue,
        now: _nowProvider(),
      );
    } finally {
      _tokens.remove(entry.id);
      _runningEntries.remove(entry.id);
      await _refreshSnapshot();
    }
  }

  Future<void> _refreshSnapshot() async {
    final entries = await _queueRepository.loadVisibleEntries();
    if (!_disposed) {
      _snapshot.value = ComicDownloadQueueSnapshot(entries: entries);
    }
  }

  String _displayTitle(String value, String fallback) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }

  ComicDownloadFailureCode _stableFailureCode(Object error) {
    if (error is ComicDownloadFailedException) {
      return error.code;
    }
    if (error is io.FileSystemException) {
      return ComicDownloadFailureCode.storageFailed;
    }
    return ComicDownloadFailureCode.unknown;
  }
}

final class _QueueProgressObserver implements ComicDownloadProgressObserver {
  const _QueueProgressObserver({required this.onProgress});

  final Future<void> Function(int completed, int total) onProgress;

  @override
  Future<void> onImagesResolved(int totalImages) {
    return onProgress(0, totalImages);
  }

  @override
  Future<void> onImageCompleted({
    required int completedImages,
    required int totalImages,
  }) {
    return onProgress(completedImages, totalImages);
  }
}
