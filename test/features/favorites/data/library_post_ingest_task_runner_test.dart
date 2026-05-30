import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/favorites/data/library_post_ingest_task_runner.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('DefaultLibraryPostIngestTaskRunner', () {
    test('canRun returns false for backfill task when coordinator is missing', () {
      const runner = DefaultLibraryPostIngestTaskRunner();

      expect(
        runner.canRun(
          const ComicAutoRefreshBackfillTask(
            comicId: 'comic:1',
            sourceTid: '100',
            favoriteTitle: 'Favorite',
          ),
        ),
        isFalse,
      );
    });

    test('ComicAutoRefreshTask delegates to coordinator.refreshAfterFavoriteIngest', () async {
      final coordinator = _RecordingAutoRefreshCoordinator();
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicAutoRefreshCoordinator: coordinator,
      );

      final task = ComicAutoRefreshTask(
        comicId: 'comic:1',
        detail: _detail(tid: '100'),
        favoriteTitle: 'Favorite Title',
        sourceTagName: '長篇連載',
        forceSearchOnCatalogMiss: true,
      );
      final report = await runner.runAll(<LibraryPostIngestTask>[task]);

      expect(coordinator.afterIngestCalls, hasLength(1));
      final call = coordinator.afterIngestCalls.single;
      expect(call.comicId, 'comic:1');
      expect(call.favoriteTitle, 'Favorite Title');
      expect(call.sourceTagName, '長篇連載');
      expect(call.forceSearchOnCatalogMiss, isTrue);
      expect(call.detail.tid, '100');
      expect(report.completed, contains(task));
      expect(report.failures, isEmpty);
      expect(report.resolvedWorkId, isNull);
    });

    test('ComicAutoRefreshTask failure is recorded but does not throw', () async {
      final coordinator = _ThrowingAutoRefreshCoordinator();
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicAutoRefreshCoordinator: coordinator,
      );

      final task = ComicAutoRefreshTask(
        comicId: 'comic:1',
        detail: _detail(tid: '100'),
        favoriteTitle: 'Favorite Title',
      );
      final report = await runner.runAll(<LibraryPostIngestTask>[task]);

      expect(report.completed, isEmpty);
      expect(report.failures, hasLength(1));
      expect(report.failures.single.task, task);
      expect(report.resolvedWorkId, isNull);
    });

    test('ComicAutoRefreshBackfillTask delegates to coordinator.refreshFavoriteComic', () async {
      final coordinator = _RecordingAutoRefreshCoordinator();
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicAutoRefreshCoordinator: coordinator,
      );

      const task = ComicAutoRefreshBackfillTask(
        comicId: 'comic:1',
        sourceTid: '100',
        favoriteTitle: 'Favorite',
        sourceTitle: 'Source',
        sourceTagName: '長篇連載',
      );
      final report = await runner.runAll(<LibraryPostIngestTask>[task]);

      expect(coordinator.backfillCalls, hasLength(1));
      final call = coordinator.backfillCalls.single;
      expect(call.comicId, 'comic:1');
      expect(call.sourceTid, '100');
      expect(call.favoriteTitle, 'Favorite');
      expect(call.sourceTitle, 'Source');
      expect(call.sourceTagName, '長篇連載');
      expect(report.completed, contains(task));
      expect(report.failures, isEmpty);
    });

    test('ComicAutoRefreshBackfillTask failure is recorded but does not throw', () async {
      final coordinator = _ThrowingAutoRefreshCoordinator();
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicAutoRefreshCoordinator: coordinator,
      );

      const task = ComicAutoRefreshBackfillTask(
        comicId: 'comic:1',
        sourceTid: '100',
        favoriteTitle: 'Favorite',
      );
      final report = await runner.runAll(<LibraryPostIngestTask>[task]);

      expect(report.completed, isEmpty);
      expect(report.failures, hasLength(1));
      expect(report.failures.single.task, task);
    });

    test('ComicDuplicateMergeTask returns merged target work id and notifies bus on change', () async {
      final repository = _FakeDuplicateMergeRepository(
        groups: const <ComicDuplicateGroup>[
          ComicDuplicateGroup(
            comicIds: <String>{'yamibo:100', 'yamibo:old'},
            sharedTids: <String>{'100'},
          ),
        ],
      );
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final reasons = <String>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          reasons.add(signal.reason);
        }
      });
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicDuplicateMergeService:
            ComicDuplicateMergeService(repository: repository),
        shelfRefreshBus: bus,
      );

      final report = await runner.runAll(<LibraryPostIngestTask>[
        const ComicDuplicateMergeTask(comicId: 'yamibo:100'),
      ]);

      expect(report.failures, isEmpty);
      expect(report.resolvedWorkId, 'yamibo:old');
      expect(reasons, contains('favorite_comic_duplicate_merge_completed'));
      expect(bus.signal.value?.source, LibraryMutationSource.duplicateMerge);
      expect(bus.signal.value?.workId, 'yamibo:old');
      expect(bus.signal.value?.payload['sourceComicId'], 'yamibo:100');
      expect(bus.signal.value?.payload['targetComicId'], 'yamibo:old');
    });

    test('ComicDuplicateMergeTask without changes leaves resolvedWorkId null', () async {
      final repository = _FakeDuplicateMergeRepository(
        groups: const <ComicDuplicateGroup>[],
      );
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final reasons = <String>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          reasons.add(signal.reason);
        }
      });
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicDuplicateMergeService:
            ComicDuplicateMergeService(repository: repository),
        shelfRefreshBus: bus,
      );

      final report = await runner.runAll(<LibraryPostIngestTask>[
        const ComicDuplicateMergeTask(comicId: 'yamibo:100'),
      ]);

      expect(report.resolvedWorkId, isNull);
      expect(reasons, isEmpty);
    });

    test('ComicDuplicateMergeTask failure is recorded and resolvedWorkId stays null', () async {
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicDuplicateMergeService: const ComicDuplicateMergeService(
          repository: _ThrowingDuplicateMergeRepository(),
        ),
      );

      final report = await runner.runAll(<LibraryPostIngestTask>[
        const ComicDuplicateMergeTask(comicId: 'yamibo:100'),
      ]);

      expect(report.failures, hasLength(1));
      expect(report.resolvedWorkId, isNull);
    });

    test('ComicDuplicateMergeAllTask emits first sync signal when changes happen', () async {
      final repository = _FakeDuplicateMergeRepository(
        groups: const <ComicDuplicateGroup>[
          ComicDuplicateGroup(
            comicIds: <String>{'yamibo:100', 'yamibo:old'},
            sharedTids: <String>{'100'},
          ),
        ],
      );
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final reasons = <String>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          reasons.add(signal.reason);
        }
      });
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicDuplicateMergeService:
            ComicDuplicateMergeService(repository: repository),
        shelfRefreshBus: bus,
      );

      final report = await runner.runAll(<LibraryPostIngestTask>[
        const ComicDuplicateMergeAllTask(),
      ]);

      expect(report.failures, isEmpty);
      expect(
        reasons,
        contains('favorite_first_sync_comic_duplicate_merge_completed'),
      );
      expect(bus.signal.value?.source, LibraryMutationSource.duplicateMerge);
      expect(bus.signal.value?.payload['removedComicCount'], 1);
    });

    test('ComicDuplicateMergeAllTask failure is recorded but does not throw', () async {
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicDuplicateMergeService: const ComicDuplicateMergeService(
          repository: _ThrowingDuplicateMergeRepository(),
        ),
      );

      final report = await runner.runAll(<LibraryPostIngestTask>[
        const ComicDuplicateMergeAllTask(),
      ]);

      expect(report.failures, hasLength(1));
    });

    test('ShelfRefreshTask forwards modules and reason to bus', () async {
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final signals = <LibraryShelfRefreshSignal>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          signals.add(signal);
        }
      });
      final runner = DefaultLibraryPostIngestTaskRunner(shelfRefreshBus: bus);

      final report = await runner.runAll(<LibraryPostIngestTask>[
        const ShelfRefreshTask(
          modules: <LibraryModuleKey>{
            LibraryModuleKey.novel,
            LibraryModuleKey.favorite,
          },
          reason: 'favorite_novel_refresh_completed',
          source: LibraryMutationSource.novelRefresh,
          workId: 'novel:49:200',
          tid: '200',
        ),
      ]);

      expect(report.failures, isEmpty);
      expect(signals, hasLength(1));
      expect(signals.single.modules, <LibraryModuleKey>{
        LibraryModuleKey.novel,
        LibraryModuleKey.favorite,
      });
      expect(signals.single.reason, 'favorite_novel_refresh_completed');
      expect(signals.single.source, LibraryMutationSource.novelRefresh);
      expect(signals.single.workId, 'novel:49:200');
      expect(signals.single.tid, '200');
    });

    test('runs multiple tasks even when a middle task fails', () async {
      final coordinator = _RecordingAutoRefreshCoordinator();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final signals = <LibraryShelfRefreshSignal>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          signals.add(signal);
        }
      });
      final runner = DefaultLibraryPostIngestTaskRunner(
        comicAutoRefreshCoordinator: coordinator,
        comicDuplicateMergeService: const ComicDuplicateMergeService(
          repository: _ThrowingDuplicateMergeRepository(),
        ),
        shelfRefreshBus: bus,
      );

      final report = await runner.runAll(<LibraryPostIngestTask>[
        ComicAutoRefreshTask(
          comicId: 'comic:1',
          detail: _detail(tid: '100'),
          favoriteTitle: 'F',
        ),
        const ComicDuplicateMergeTask(comicId: 'yamibo:100'),
        const ShelfRefreshTask(
          modules: <LibraryModuleKey>{LibraryModuleKey.favorite},
          reason: 'favorite_sync_completed',
          source: LibraryMutationSource.favoriteSync,
        ),
      ]);

      expect(coordinator.afterIngestCalls, hasLength(1));
      expect(report.failures, hasLength(1));
      expect(report.completed, hasLength(2));
      expect(signals.last.reason, 'favorite_sync_completed');
      expect(signals.last.source, LibraryMutationSource.favoriteSync);
    });

    test('empty task list yields empty report without touching bus', () async {
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final runner = DefaultLibraryPostIngestTaskRunner(shelfRefreshBus: bus);

      final report = await runner.runAll(const <LibraryPostIngestTask>[]);

      expect(report.completed, isEmpty);
      expect(report.failures, isEmpty);
      expect(bus.signal.value, isNull);
    });
  });
}

ThreadDetailData _detail({required String tid}) {
  return ThreadDetailData(
    tid: tid,
    fid: '30',
    typeid: '398',
    subject: '主题$tid',
    author: '作者',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: const <ThreadPost>[],
  );
}

class _AutoRefreshCallRecord {
  _AutoRefreshCallRecord({
    required this.comicId,
    required this.detail,
    required this.favoriteTitle,
    required this.sourceTagName,
    required this.forceSearchOnCatalogMiss,
  });

  final String comicId;
  final ThreadDetailData detail;
  final String favoriteTitle;
  final String? sourceTagName;
  final bool forceSearchOnCatalogMiss;
}

class _BackfillCallRecord {
  _BackfillCallRecord({
    required this.comicId,
    required this.sourceTid,
    required this.favoriteTitle,
    required this.sourceTitle,
    required this.sourceTagName,
  });

  final String comicId;
  final String sourceTid;
  final String favoriteTitle;
  final String? sourceTitle;
  final String? sourceTagName;
}

class _RecordingAutoRefreshCoordinator
    extends ComicFavoriteAutoRefreshCoordinator {
  _RecordingAutoRefreshCoordinator()
      : super(
          refreshService: _NoopRefreshService(),
          searchQueue: _NoopSearchQueue(),
          refreshOutcomeApplier: const _NoopRefreshOutcomeApplier(),
          shelfRefreshBus: _UnusedBus.instance,
          catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
          subjectParser: const RuleBasedComicSubjectParser(),
        );

  final List<_AutoRefreshCallRecord> afterIngestCalls =
      <_AutoRefreshCallRecord>[];
  final List<_BackfillCallRecord> backfillCalls = <_BackfillCallRecord>[];

  @override
  Future<ComicFavoriteAutoRefreshResult> refreshAfterFavoriteIngest({
    required String comicId,
    required ThreadDetailData detail,
    required String favoriteTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) async {
    afterIngestCalls.add(
      _AutoRefreshCallRecord(
        comicId: comicId,
        detail: detail,
        favoriteTitle: favoriteTitle,
        sourceTagName: sourceTagName,
        forceSearchOnCatalogMiss: forceSearchOnCatalogMiss,
      ),
    );
    return const ComicFavoriteAutoRefreshResult(
      status: ComicFavoriteAutoRefreshStatus.skipped,
    );
  }

  @override
  Future<ComicFavoriteAutoRefreshResult> refreshFavoriteComic({
    required String comicId,
    required String sourceTid,
    required String favoriteTitle,
    String? sourceTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) async {
    backfillCalls.add(
      _BackfillCallRecord(
        comicId: comicId,
        sourceTid: sourceTid,
        favoriteTitle: favoriteTitle,
        sourceTitle: sourceTitle,
        sourceTagName: sourceTagName,
      ),
    );
    return const ComicFavoriteAutoRefreshResult(
      status: ComicFavoriteAutoRefreshStatus.skipped,
    );
  }
}

class _ThrowingAutoRefreshCoordinator
    extends ComicFavoriteAutoRefreshCoordinator {
  _ThrowingAutoRefreshCoordinator()
      : super(
          refreshService: _NoopRefreshService(),
          searchQueue: _NoopSearchQueue(),
          refreshOutcomeApplier: const _NoopRefreshOutcomeApplier(),
          shelfRefreshBus: _UnusedBus.instance,
          catalogMissPolicy: const DefaultComicCatalogMissPolicy(),
          subjectParser: const RuleBasedComicSubjectParser(),
        );

  @override
  Future<ComicFavoriteAutoRefreshResult> refreshAfterFavoriteIngest({
    required String comicId,
    required ThreadDetailData detail,
    required String favoriteTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicFavoriteAutoRefreshResult> refreshFavoriteComic({
    required String comicId,
    required String sourceTid,
    required String favoriteTitle,
    String? sourceTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) {
    throw StateError('refresh failed');
  }
}

class _NoopRefreshOutcomeApplier implements ComicRefreshOutcomeApplier {
  const _NoopRefreshOutcomeApplier();

  @override
  Future<ComicRefreshApplyResult> apply(
    ComicRefreshApplyRequest request,
  ) async {
    return const ComicRefreshApplyResult.skipped();
  }
}

class _NoopRefreshService implements ComicEpisodeRefreshService {
  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const <ComicEpisodeLink>[];
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return const <ComicEpisodeLink>[];
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }
}

class _NoopSearchQueue implements ComicSearchRefreshQueueEnqueuer {
  @override
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
  }) async {
    return ComicSearchRefreshEnqueueResult(
      entry: ComicSearchRefreshQueueEntry(
        id: 1,
        comicId: request.comicId ?? '',
        title: title,
        request: request,
        origin: origin,
        status: ComicSearchRefreshQueueStatus.pending,
        attempts: 0,
        availableAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      position: 1,
      estimatedDuration: const Duration(milliseconds: 10500),
      deduplicated: false,
    );
  }
}

class _UnusedBus {
  static final LibraryShelfRefreshBus instance = LibraryShelfRefreshBus();
}

class _FakeDuplicateMergeRepository implements ComicDuplicateMergeRepository {
  _FakeDuplicateMergeRepository({
    required List<ComicDuplicateGroup> groups,
  }) : _groups = groups.toList(growable: true);

  final List<ComicDuplicateGroup> _groups;

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) async {
    final query = comicId?.trim();
    if (query == null || query.isEmpty) {
      return List<ComicDuplicateGroup>.unmodifiable(_groups);
    }
    return _groups
        .where((group) => group.comicIds.contains(query))
        .toList(growable: false);
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    final target = comicIds.contains('yamibo:old') ? 'yamibo:old' : comicIds.first;
    final removed = comicIds.where((comicId) => comicId != target).toSet();
    return ComicDuplicateMergeResult(
      targetComicId: target,
      targetTitle: '短标题',
      mergedComicIds: removed,
      replacements: <String, String>{
        for (final comicId in removed) comicId: target,
      },
      movedEpisodeCount: removed.length,
    );
  }
}

class _ThrowingDuplicateMergeRepository implements ComicDuplicateMergeRepository {
  const _ThrowingDuplicateMergeRepository();

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) {
    throw StateError('merge failed');
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) {
    throw StateError('merge failed');
  }
}
