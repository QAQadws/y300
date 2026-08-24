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
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef NovelChapterSyncClock = DateTime Function();
typedef NovelChapterSyncRunIdFactory =
    String Function(String novelId, DateTime startedAt);

class DefaultNovelChapterSyncService implements NovelChapterSyncService {
  DefaultNovelChapterSyncService({
    required NovelThreadGateway threadGateway,
    required NovelSyncRequestGovernor governor,
    required NovelAuthorPostEpisodeBuilder episodeBuilder,
    required NovelTitleSanitizer titleSanitizer,
    required NovelChapterSyncRepository repository,
    required NovelSourceStateRepository sourceStateRepository,
    LibraryShelfRefreshBus? shelfRefreshBus,
    NovelChapterSyncClock? clock,
    NovelChapterSyncRunIdFactory? runIdFactory,
    this.maxAuthorPages = 10000,
  }) : _threadGateway = threadGateway,
       _governor = governor,
       _episodeBuilder = episodeBuilder,
       _titleSanitizer = titleSanitizer,
       _repository = repository,
       _sourceStateRepository = sourceStateRepository,
       _shelfRefreshBus = shelfRefreshBus,
       _clock = clock ?? DateTime.now,
       _runIdFactory = runIdFactory ?? _defaultRunId;

  final NovelThreadGateway _threadGateway;
  final NovelSyncRequestGovernor _governor;
  final NovelAuthorPostEpisodeBuilder _episodeBuilder;
  final NovelTitleSanitizer _titleSanitizer;
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
    final novelId = _requireText(request.novelId, 'request.novelId');
    final tid = _requireText(request.tid, 'request.tid');
    final publisherId = _requireText(
      request.publisherId,
      'request.publisherId',
    );
    final persistedCheckpoint = _validatedCheckpoint(
      request: request,
      novelId: novelId,
      publisherId: publisherId,
    );
    final startedAt = _clock();
    final runId = _runIdFactory(novelId, startedAt);
    var page = request.mode == NovelChapterSyncMode.incremental
        ? persistedCheckpoint!.lastCompletedAuthorPage
        : 1;
    var fetchedPages = 0;
    var acceptedCount = 0;
    var totalPages = page;
    var lastSeenPid = persistedCheckpoint?.lastSeenPid;
    String? sourceTitle;
    var runBegan = false;
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
      runBegan = true;
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
        fetchedPages++;
        if (detail.tid.trim().isNotEmpty && detail.tid.trim() != tid) {
          throw StateError(
            'Author-filtered response tid does not match its request.',
          );
        }
        if (detail.currentPage > 0 && detail.currentPage != page) {
          throw StateError(
            'Author-filtered response page ${detail.currentPage} does not '
            'match requested page $page.',
          );
        }
        totalPages = _estimatedTotalPages(detail);
        if (detail.posts.isEmpty && detail.hasMore) {
          throw StateError(
            'Author-filtered page $page is empty before the last page.',
          );
        }
        if (fetchedPages == 1) {
          final sanitizedTitle = _titleSanitizer.sanitize(detail.subject);
          sourceTitle = sanitizedTitle.isEmpty ? null : sanitizedTitle;
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
        fetchedPages: fetchedPages,
        sourceTitle: sourceTitle,
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
        reason: switch (request.mode) {
          NovelChapterSyncMode.initialFull =>
            'novel_initial_chapter_hydration_completed',
          NovelChapterSyncMode.incremental =>
            'novel_incremental_chapter_sync_completed',
          NovelChapterSyncMode.fullRefresh =>
            'novel_full_chapter_refresh_completed',
        },
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
      if (runBegan) {
        try {
          final failureCode = _failureCode(error);
          await _sourceStateRepository.setHydrationState(
            novelId: novelId,
            state: request.mode == NovelChapterSyncMode.initialFull
                ? NovelChapterHydrationState.failed
                : NovelChapterHydrationState.ready,
            lastError: failureCode.storageValue,
          );
        } catch (_) {
          // A missing source row is already represented by the original error.
        }
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
          failureCode: _failureCode(error),
          diagnosticDetail: error is NovelChapterSyncException
              ? error.detail
              : error,
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

  NovelChapterSyncCheckpoint? _validatedCheckpoint({
    required NovelChapterSyncRequest request,
    required String novelId,
    required String publisherId,
  }) {
    if (request.mode != NovelChapterSyncMode.incremental) {
      return request.checkpoint;
    }
    final checkpoint = request.checkpoint;
    if (checkpoint == null) {
      throw StateError(
        'Incremental novel synchronization requires a persisted checkpoint.',
      );
    }
    if (checkpoint.novelId.trim() != novelId ||
        checkpoint.publisherId.trim() != publisherId ||
        checkpoint.lastCompletedAuthorPage < 1) {
      throw StateError(
        'Incremental novel synchronization checkpoint does not match its '
        'request.',
      );
    }
    return checkpoint;
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

  NovelChapterSyncFailureCode _failureCode(Object error) {
    return error is NovelChapterSyncException
        ? error.code
        : NovelChapterSyncFailureCode.synchronizationFailed;
  }

  static String _defaultRunId(String novelId, DateTime startedAt) {
    return '${startedAt.microsecondsSinceEpoch}:${novelId.hashCode}';
  }
}
