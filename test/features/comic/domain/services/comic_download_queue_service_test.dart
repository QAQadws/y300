import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/repositories/comic_download_queue_repository.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_execution.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue_service.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/storage/domain/download_storage_models.dart';

void main() {
  test(
    'runs FIFO, keeps failures, and continues with the next entry',
    () async {
      final repository = _MemoryQueueRepository();
      final now = DateTime(2026, 7, 22, 13);
      await repository.enqueueTargets(<ComicDownloadTarget>[
        _target('episode:1'),
        _target('episode:2'),
        _target('episode:3'),
      ], now: now);
      final downloadService = _RecordingDownloadService(
        failures: const <String>{'episode:2'},
      );
      final stateRepository = _RecordingLibraryStateRepository();
      final refreshBus = LibraryShelfRefreshBus();
      addTearDown(refreshBus.dispose);
      final service = ComicDownloadQueueService(
        queueRepository: repository,
        downloadService: downloadService,
        libraryStateRepository: stateRepository,
        shelfRefreshBus: refreshBus,
        nowProvider: () => now,
      );
      addTearDown(service.dispose);

      await service.start();
      await service.drainForTest();

      expect(downloadService.episodeIds, <String>[
        'episode:1',
        'episode:2',
        'episode:3',
      ]);
      expect(stateRepository.downloadedEpisodeIds, <String>[
        'episode:1',
        'episode:3',
      ]);
      final visible = repository.entries;
      expect(visible, hasLength(1));
      expect(visible.single.episodeId, 'episode:2');
      expect(visible.single.status, ComicDownloadQueueStatus.failed);
      expect(visible.single.lastError, 'download failed for episode:2');
      expect(service.snapshot.value.failedCount, 1);
    },
  );

  test('cooperatively cancels a running entry and removes it', () async {
    final repository = _MemoryQueueRepository();
    final now = DateTime(2026, 7, 22, 14);
    await repository.enqueueTargets(<ComicDownloadTarget>[
      _target('episode:1'),
    ], now: now);
    final downloadService = _BlockingDownloadService();
    final stateRepository = _RecordingLibraryStateRepository();
    final refreshBus = LibraryShelfRefreshBus();
    addTearDown(refreshBus.dispose);
    final service = ComicDownloadQueueService(
      queueRepository: repository,
      downloadService: downloadService,
      libraryStateRepository: stateRepository,
      shelfRefreshBus: refreshBus,
      nowProvider: () => now,
    );
    addTearDown(service.dispose);

    await service.start();
    await downloadService.started.future;
    final active = service.snapshot.value.activeEntry;
    expect(active, isNotNull);

    await service.cancel(active!.id);
    expect(
      service.snapshot.value.activeEntry?.status,
      ComicDownloadQueueStatus.cancelRequested,
    );
    downloadService.release.complete();
    await service.drainForTest();

    expect(repository.entries, isEmpty);
    expect(stateRepository.downloadedEpisodeIds, isEmpty);
    expect(service.snapshot.value.isEmpty, isTrue);
  });

  test('startup resets an interrupted running entry and resumes it', () async {
    final repository = _MemoryQueueRepository();
    final now = DateTime(2026, 7, 22, 15);
    await repository.enqueueTargets(<ComicDownloadTarget>[
      _target('episode:1'),
    ], now: now);
    await repository.claimNext(now: now);
    expect(repository.entries.single.status, ComicDownloadQueueStatus.running);
    final downloadService = _RecordingDownloadService();
    final stateRepository = _RecordingLibraryStateRepository();
    final refreshBus = LibraryShelfRefreshBus();
    addTearDown(refreshBus.dispose);
    final service = ComicDownloadQueueService(
      queueRepository: repository,
      downloadService: downloadService,
      libraryStateRepository: stateRepository,
      shelfRefreshBus: refreshBus,
      nowProvider: () => now,
    );
    addTearDown(service.dispose);

    await service.start();
    await service.drainForTest();

    expect(downloadService.episodeIds, <String>['episode:1']);
    expect(repository.entries, isEmpty);
    expect(stateRepository.downloadedEpisodeIds, <String>['episode:1']);
  });

  test('retry moves a failed entry back through the same worker', () async {
    final repository = _MemoryQueueRepository();
    final now = DateTime(2026, 7, 22, 16);
    await repository.enqueueTargets(<ComicDownloadTarget>[
      _target('episode:1'),
    ], now: now);
    final failures = <String>{'episode:1'};
    final downloadService = _RecordingDownloadService(failures: failures);
    final stateRepository = _RecordingLibraryStateRepository();
    final refreshBus = LibraryShelfRefreshBus();
    addTearDown(refreshBus.dispose);
    final service = ComicDownloadQueueService(
      queueRepository: repository,
      downloadService: downloadService,
      libraryStateRepository: stateRepository,
      shelfRefreshBus: refreshBus,
      nowProvider: () => now,
    );
    addTearDown(service.dispose);

    await service.start();
    await service.drainForTest();
    final failed = repository.entries.single;
    expect(failed.status, ComicDownloadQueueStatus.failed);

    failures.clear();
    await service.retry(failed.id);
    await service.drainForTest();

    expect(downloadService.episodeIds, <String>['episode:1', 'episode:1']);
    expect(repository.entries, isEmpty);
    expect(stateRepository.downloadedEpisodeIds, <String>['episode:1']);
  });
}

ComicDownloadTarget _target(String episodeId) {
  return ComicDownloadTarget(
    comicId: 'comic:1',
    episodeId: episodeId,
    comicTitle: '作品',
    episodeTitle: episodeId,
  );
}

final class _MemoryQueueRepository implements ComicDownloadQueueRepository {
  final List<ComicDownloadQueueEntry> _entries = <ComicDownloadQueueEntry>[];
  var _nextId = 1;

  List<ComicDownloadQueueEntry> get entries => List.unmodifiable(_entries);

  @override
  Future<ComicDownloadRepositoryEnqueueResult> enqueueTargets(
    List<ComicDownloadTarget> targets, {
    required DateTime now,
  }) async {
    var enqueued = 0;
    var deduplicated = 0;
    for (final target in targets) {
      final index = _entries.indexWhere(
        (entry) =>
            entry.comicId == target.comicId &&
            entry.episodeId == target.episodeId,
      );
      if (index >= 0) {
        if (_entries[index].status == ComicDownloadQueueStatus.failed) {
          _entries[index] = _copyEntry(
            _entries[index],
            status: ComicDownloadQueueStatus.pending,
            completedImages: 0,
            clearError: true,
            updatedAt: now,
          );
          enqueued += 1;
        } else {
          deduplicated += 1;
        }
        continue;
      }
      _entries.add(
        ComicDownloadQueueEntry(
          id: _nextId++,
          comicId: target.comicId,
          episodeId: target.episodeId,
          comicTitle: target.comicTitle,
          episodeTitle: target.episodeTitle,
          status: ComicDownloadQueueStatus.pending,
          completedImages: 0,
          totalImages: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
      enqueued += 1;
    }
    return ComicDownloadRepositoryEnqueueResult(
      enqueuedCount: enqueued,
      deduplicatedCount: deduplicated,
    );
  }

  @override
  Future<void> recoverInterrupted({required DateTime now}) async {
    _entries.removeWhere(
      (entry) => entry.status == ComicDownloadQueueStatus.cancelRequested,
    );
    for (var index = 0; index < _entries.length; index++) {
      if (_entries[index].status == ComicDownloadQueueStatus.running) {
        _entries[index] = _copyEntry(
          _entries[index],
          status: ComicDownloadQueueStatus.pending,
          updatedAt: now,
        );
      }
    }
  }

  @override
  Future<ComicDownloadQueueEntry?> claimNext({required DateTime now}) async {
    final candidates =
        _entries
            .where((entry) => entry.status == ComicDownloadQueueStatus.pending)
            .toList()
          ..sort((a, b) {
            final byCreated = a.createdAt.compareTo(b.createdAt);
            return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
          });
    if (candidates.isEmpty) {
      return null;
    }
    final index = _indexOf(candidates.first.id);
    final claimed = _copyEntry(
      _entries[index],
      status: ComicDownloadQueueStatus.running,
      updatedAt: now,
    );
    _entries[index] = claimed;
    return claimed;
  }

  @override
  Future<List<ComicDownloadQueueEntry>> loadVisibleEntries() async {
    return List<ComicDownloadQueueEntry>.unmodifiable(_entries);
  }

  @override
  Future<ComicDownloadQueueEntry?> getById(int id) async {
    final index = _indexOf(id);
    return index < 0 ? null : _entries[index];
  }

  @override
  Future<void> updateProgress({
    required int id,
    required int completedImages,
    required int totalImages,
    required DateTime now,
  }) async {
    final index = _indexOf(id);
    if (index >= 0) {
      _entries[index] = _copyEntry(
        _entries[index],
        completedImages: completedImages,
        totalImages: totalImages,
        updatedAt: now,
      );
    }
  }

  @override
  Future<void> markFailed({
    required int id,
    required String error,
    required DateTime now,
  }) async {
    final index = _indexOf(id);
    if (index >= 0) {
      _entries[index] = _copyEntry(
        _entries[index],
        status: ComicDownloadQueueStatus.failed,
        lastError: error,
        updatedAt: now,
      );
    }
  }

  @override
  Future<void> requestCancel({required int id, required DateTime now}) async {
    final index = _indexOf(id);
    if (index >= 0 &&
        _entries[index].status == ComicDownloadQueueStatus.running) {
      _entries[index] = _copyEntry(
        _entries[index],
        status: ComicDownloadQueueStatus.cancelRequested,
        updatedAt: now,
      );
    }
  }

  @override
  Future<void> retry({required int id, required DateTime now}) async {
    final index = _indexOf(id);
    if (index >= 0 &&
        _entries[index].status == ComicDownloadQueueStatus.failed) {
      _entries[index] = _copyEntry(
        _entries[index],
        status: ComicDownloadQueueStatus.pending,
        completedImages: 0,
        clearError: true,
        updatedAt: now,
      );
    }
  }

  @override
  Future<void> delete(int id) async {
    _entries.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<bool> deleteIfNotRunning(int id) async {
    final index = _indexOf(id);
    if (index < 0) {
      return false;
    }
    final status = _entries[index].status;
    if (status == ComicDownloadQueueStatus.running ||
        status == ComicDownloadQueueStatus.cancelRequested) {
      return false;
    }
    _entries.removeAt(index);
    return true;
  }

  @override
  Future<void> deleteByEpisode(String comicId, String episodeId) async {
    _entries.removeWhere(
      (entry) => entry.comicId == comicId && entry.episodeId == episodeId,
    );
  }

  @override
  Future<void> deleteByComic(String comicId) async {
    _entries.removeWhere((entry) => entry.comicId == comicId);
  }

  int _indexOf(int id) => _entries.indexWhere((entry) => entry.id == id);
}

ComicDownloadQueueEntry _copyEntry(
  ComicDownloadQueueEntry entry, {
  ComicDownloadQueueStatus? status,
  int? completedImages,
  int? totalImages,
  String? lastError,
  bool clearError = false,
  DateTime? updatedAt,
}) {
  return ComicDownloadQueueEntry(
    id: entry.id,
    comicId: entry.comicId,
    episodeId: entry.episodeId,
    comicTitle: entry.comicTitle,
    episodeTitle: entry.episodeTitle,
    status: status ?? entry.status,
    completedImages: completedImages ?? entry.completedImages,
    totalImages: totalImages ?? entry.totalImages,
    lastError: clearError ? null : lastError ?? entry.lastError,
    createdAt: entry.createdAt,
    updatedAt: updatedAt ?? entry.updatedAt,
  );
}

class _RecordingDownloadService implements ComicDownloadService {
  _RecordingDownloadService({this.failures = const <String>{}});

  final Set<String> failures;
  final List<String> episodeIds = <String>[];

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  }) async {
    episodeIds.add(episodeId);
    await observer?.onImagesResolved(2);
    await observer?.onImageCompleted(completedImages: 1, totalImages: 2);
    cancellationToken?.throwIfCancellationRequested();
    if (failures.contains(episodeId)) {
      throw StateError('download failed for $episodeId');
    }
    await observer?.onImageCompleted(completedImages: 2, totalImages: 2);
    return DownloadedComicEpisode(
      workId: comicId,
      episodeId: episodeId,
      cbzPath: '$episodeId.cbz',
      imageFiles: const <String>['001.jpg', '002.jpg'],
    );
  }

  @override
  Future<void> deleteEpisodeDownload({
    required String comicId,
    required String episodeId,
  }) async {}

  @override
  Future<List<ComicEpisodeImageItem>> getDownloadedEpisodeImages({
    required String comicId,
    required String episodeId,
  }) async => const <ComicEpisodeImageItem>[];
}

final class _BlockingDownloadService extends _RecordingDownloadService {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<DownloadedComicEpisode> downloadEpisode({
    required String comicId,
    required String episodeId,
    ComicDownloadProgressObserver? observer,
    ComicDownloadCancellationToken? cancellationToken,
  }) async {
    await observer?.onImagesResolved(2);
    started.complete();
    await release.future;
    cancellationToken?.throwIfCancellationRequested();
    return super.downloadEpisode(
      comicId: comicId,
      episodeId: episodeId,
      observer: observer,
      cancellationToken: cancellationToken,
    );
  }
}

final class _RecordingLibraryStateRepository implements LibraryStateRepository {
  final List<String> downloadedEpisodeIds = <String>[];

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async => null;

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    if (isDownloaded == true) {
      downloadedEpisodeIds.add(episodeId);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
