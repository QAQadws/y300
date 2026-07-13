import 'dart:async';
import 'dart:developer' as developer;

import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_episode_builder.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/services/novel_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

typedef NovelChapterSyncClock = DateTime Function();
typedef NovelChapterSyncRunIdFactory =
    String Function(String novelId, DateTime startedAt);

class DefaultNovelChapterSyncService implements NovelChapterSyncService {
  DefaultNovelChapterSyncService({
    required NovelThreadGateway threadGateway,
    required NovelSyncRequestGovernor governor,
    required NovelAuthorPostEpisodeBuilder episodeBuilder,
    required NovelChapterSyncRepository repository,
    required NovelSourceStateRepository sourceStateRepository,
    LibraryShelfRefreshBus? shelfRefreshBus,
    NovelChapterSyncClock? clock,
    NovelChapterSyncRunIdFactory? runIdFactory,
    this.maxAuthorPages = 10000,
  }) : _threadGateway = threadGateway,
       _governor = governor,
       _episodeBuilder = episodeBuilder,
       _repository = repository,
       _sourceStateRepository = sourceStateRepository,
       _shelfRefreshBus = shelfRefreshBus,
       _clock = clock ?? DateTime.now,
       _runIdFactory = runIdFactory ?? _defaultRunId;

  final NovelThreadGateway _threadGateway;
  final NovelSyncRequestGovernor _governor;
  final NovelAuthorPostEpisodeBuilder _episodeBuilder;
  final NovelChapterSyncRepository _repository;
  final NovelSourceStateRepository _sourceStateRepository;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final NovelChapterSyncClock _clock;
  final NovelChapterSyncRunIdFactory _runIdFactory;
  final int maxAuthorPages;

  final Map<String, Future<NovelChapterSyncResult>> _inflight =
      <String, Future<NovelChapterSyncResult>>{};
  final Map<String, StreamController<NovelChapterSyncProgress>>
  _progressControllers = <String, StreamController<NovelChapterSyncProgress>>{};

  @override
  bool hasActiveRun(String novelId) => _inflight.containsKey(novelId.trim());

  @override
  Stream<NovelChapterSyncProgress> watchProgress(String novelId) {
    return _progressController(novelId.trim()).stream;
  }

  @override
  Future<NovelChapterSyncResult> synchronize(NovelChapterSyncRequest request) {
    final novelId = _requireText(request.novelId, 'request.novelId');
    final existing = _inflight[novelId];
    if (existing != null) {
      return existing;
    }
    final run = _run(request);
    _inflight[novelId] = run;
    unawaited(
      run.then<void>(
        (_) => _removeInflight(novelId, run),
        onError: (_, _) => _removeInflight(novelId, run),
      ),
    );
    return run;
  }

  Future<NovelChapterSyncResult> _run(NovelChapterSyncRequest request) async {
    if (request.mode != NovelChapterSyncMode.initialFull) {
      throw UnsupportedError(
        'Incremental novel synchronization is introduced in Phase 5.',
      );
    }
    final novelId = _requireText(request.novelId, 'request.novelId');
    final tid = _requireText(request.tid, 'request.tid');
    final publisherId = _requireText(
      request.publisherId,
      'request.publisherId',
    );
    final startedAt = _clock();
    final runId = _runIdFactory(novelId, startedAt);
    var page = 1;
    var acceptedCount = 0;
    var totalPages = 1;
    String? lastSeenPid;
    final seenPids = <String>{};

    _emit(
      NovelChapterSyncProgress(
        runId: runId,
        novelId: novelId,
        mode: request.mode,
        phase: NovelChapterSyncPhase.preparing,
      ),
    );

    try {
      await _repository.beginRun(
        runId: runId,
        novelId: novelId,
        mode: request.mode,
      );
      while (true) {
        if (page > maxAuthorPages) {
          throw StateError(
            'Author-filtered crawl exceeded the defensive page limit '
            '($maxAuthorPages).',
          );
        }
        _emit(
          NovelChapterSyncProgress(
            runId: runId,
            novelId: novelId,
            mode: request.mode,
            phase: NovelChapterSyncPhase.fetchingPage,
            currentPage: page,
            totalPages: totalPages,
            acceptedCount: acceptedCount,
          ),
        );
        final detail = await _governor.schedule(
          () => _threadGateway.loadAuthorPostsPage(
            tid: tid,
            authorId: publisherId,
            page: page,
            postsPerPage: 200,
          ),
        );
        if (detail.tid.trim().isNotEmpty && detail.tid.trim() != tid) {
          throw StateError(
            'Author-filtered response tid does not match its request.',
          );
        }
        totalPages = _estimatedTotalPages(detail);
        if (detail.posts.isEmpty && detail.hasMore) {
          throw StateError(
            'Author-filtered page $page is empty before the last page.',
          );
        }

        _emit(
          NovelChapterSyncProgress(
            runId: runId,
            novelId: novelId,
            mode: request.mode,
            phase: NovelChapterSyncPhase.parsingPage,
            currentPage: page,
            totalPages: totalPages,
            acceptedCount: acceptedCount,
          ),
        );
        final drafts = <NovelEpisodeDraft>[];
        for (final post in detail.posts) {
          final pid = post.pid.trim();
          if (pid.isEmpty || seenPids.contains(pid)) {
            continue;
          }
          final draft = _episodeBuilder.build(
            novelId: novelId,
            tid: tid,
            publisherId: publisherId,
            post: post,
            authorFilteredPage: page,
            orderIndex: acceptedCount,
          );
          if (draft == null) {
            continue;
          }
          seenPids.add(pid);
          drafts.add(draft);
          acceptedCount++;
          lastSeenPid = pid;
        }
        await _repository.stageEpisodes(runId: runId, episodes: drafts);
        if (!detail.hasMore) {
          break;
        }
        page++;
      }

      if (acceptedCount == 0) {
        throw StateError('No valid publisher chapters were found.');
      }
      final checkpoint = NovelChapterSyncCheckpoint(
        novelId: novelId,
        publisherId: publisherId,
        lastCompletedAuthorPage: page,
        lastSeenPid: lastSeenPid,
        completedAt: _clock(),
      );
      _emit(
        NovelChapterSyncProgress(
          runId: runId,
          novelId: novelId,
          mode: request.mode,
          phase: NovelChapterSyncPhase.committing,
          currentPage: page,
          totalPages: totalPages,
          acceptedCount: acceptedCount,
        ),
      );
      final result = await _repository.promote(
        runId: runId,
        request: request,
        checkpoint: checkpoint,
        fetchedPages: page,
      );
      _emit(
        NovelChapterSyncProgress(
          runId: runId,
          novelId: novelId,
          mode: request.mode,
          phase: NovelChapterSyncPhase.completed,
          currentPage: page,
          totalPages: totalPages,
          acceptedCount: acceptedCount,
        ),
      );
      _shelfRefreshBus?.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.novel},
        reason: 'novel_initial_chapter_hydration_completed',
        source: LibraryMutationSource.novelRefresh,
        workId: novelId,
        tid: tid,
        payload: <String, Object?>{
          'insertedCount': result.insertedCount,
          'updatedCount': result.updatedCount,
          'totalCount': result.totalCount,
        },
      );
      return result;
    } catch (error, stackTrace) {
      try {
        await _repository.discardRun(runId);
      } catch (_) {
        // Preserve the synchronization error; stale staging is removed by the
        // next beginRun for this novel.
      }
      try {
        await _sourceStateRepository.setHydrationState(
          novelId: novelId,
          state: NovelChapterHydrationState.failed,
          lastError: _errorMessage(error),
        );
      } catch (_) {
        // A missing source row is already represented by the original error.
      }
      _emit(
        NovelChapterSyncProgress(
          runId: runId,
          novelId: novelId,
          mode: request.mode,
          phase: NovelChapterSyncPhase.failed,
          currentPage: page,
          totalPages: totalPages,
          acceptedCount: acceptedCount,
          message: _errorMessage(error),
        ),
      );
      developer.log(
        'Novel chapter synchronization failed',
        name: 'NovelChapterSync',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  int _estimatedTotalPages(ThreadDetailData detail) {
    final perPage = detail.perPage <= 0 ? 200 : detail.perPage;
    final estimate = (detail.replies ~/ perPage) + 1;
    return estimate < detail.currentPage ? detail.currentPage : estimate;
  }

  void _removeInflight(String novelId, Future<NovelChapterSyncResult> run) {
    if (identical(_inflight[novelId], run)) {
      _inflight.remove(novelId);
    }
  }

  void _emit(NovelChapterSyncProgress progress) {
    _progressController(progress.novelId).add(progress);
  }

  StreamController<NovelChapterSyncProgress> _progressController(
    String novelId,
  ) {
    return _progressControllers.putIfAbsent(
      novelId,
      () => StreamController<NovelChapterSyncProgress>.broadcast(),
    );
  }

  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
  }

  String _requireText(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }

  String _errorMessage(Object error) {
    return error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _defaultRunId(String novelId, DateTime startedAt) {
    return '${startedAt.microsecondsSinceEpoch}:${novelId.hashCode}';
  }
}
