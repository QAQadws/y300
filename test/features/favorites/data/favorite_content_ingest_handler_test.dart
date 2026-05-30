import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/favorites/data/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/favorite_detail_context.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  group('ComicFavoriteContentIngestHandler', () {
    test('ingests comic and returns original work id by default', () async {
      final ingestService = _FakeComicIngestService();
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: ingestService,
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
          tagName: '韩国漫画',
        ),
      );

      expect(ingestService.upsertedTids, <String>['100']);
      expect(result.kind, ThreadContentKind.comic);
      expect(result.workId, 'yamibo:100');
      expect(result.postTasks, isEmpty);
    });

    test('swallows auto refresh failure and keeps ingested work id', () async {
      final ingestService = _FakeComicIngestService();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: ingestService,
        comicAutoRefreshCoordinator: ComicFavoriteAutoRefreshCoordinator(
          repository: _RecordingComicRepository(),
          refreshService: const _ThrowingRefreshService(),
          searchQueue: _RecordingSearchQueue(),
          firstEpisodeCoverPromoter: _RecordingCoverPromoter(),
          shelfRefreshBus: bus,
          subjectParser: const RuleBasedComicSubjectParser(),
        ),
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
        ),
      );

      expect(ingestService.upsertedTids, <String>['100']);
      expect(result.workId, 'yamibo:100');
    });

    test('returns merged target work id when duplicate merge changes comic', () async {
      final ingestService = _FakeComicIngestService();
      final duplicateRepository = _FakeDuplicateMergeRepository(
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
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: ingestService,
        comicDuplicateMergeService: ComicDuplicateMergeService(
          repository: duplicateRepository,
        ),
        shelfRefreshBus: bus,
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
        ),
      );

      expect(duplicateRepository.mergeComicIds, <String>['yamibo:100']);
      expect(result.workId, 'yamibo:old');
      expect(reasons, contains('favorite_comic_duplicate_merge_completed'));
    });

    test('returns original work id when duplicate merge fails', () async {
      final ingestService = _FakeComicIngestService();
      final handler = ComicFavoriteContentIngestHandler(
        ingestService: ingestService,
        comicDuplicateMergeService: const ComicDuplicateMergeService(
          repository: _ThrowingDuplicateMergeRepository(),
        ),
      );

      final result = await handler.ingest(
        _request(
          tid: '100',
          fid: '30',
          typeid: '398',
          kind: ThreadContentKind.comic,
        ),
      );

      expect(result.workId, 'yamibo:100');
    });
  });

  group('NovelFavoriteContentIngestHandler', () {
    test('notifies novel refresh completion after ingest', () async {
      final ingestService = _FakeNovelIngestService();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final reasons = <String>[];
      bus.signal.addListener(() {
        final signal = bus.signal.value;
        if (signal != null) {
          reasons.add(signal.reason);
        }
      });
      final handler = NovelFavoriteContentIngestHandler(
        ingestService: ingestService,
        shelfRefreshBus: bus,
      );

      final result = await handler.ingest(
        _request(
          tid: '200',
          fid: '49',
          typeid: '293',
          kind: ThreadContentKind.novel,
          tagName: '原创',
        ),
      );

      expect(ingestService.upsertedTids, <String>['200']);
      expect(result.kind, ThreadContentKind.novel);
      expect(result.workId, 'novel:49:200');
      expect(reasons, contains('favorite_novel_refresh_completed'));
    });
  });

  group('ForumFavoriteContentIngestHandler', () {
    test('returns thread work id and removeFromShelf is a no-op', () async {
      final handler = const ForumFavoriteContentIngestHandler();

      final result = await handler.ingest(
        _request(
          tid: '300',
          fid: '1',
          kind: ThreadContentKind.forum,
        ),
      );
      await handler.removeFromShelf(workId: 'thread:300');

      expect(result.kind, ThreadContentKind.forum);
      expect(result.workId, 'thread:300');
      expect(result.postTasks, isEmpty);
    });
  });
}

FavoriteContentIngestRequest _request({
  required String tid,
  required String fid,
  required ThreadContentKind kind,
  String typeid = '',
  String? tagName,
}) {
  return FavoriteContentIngestRequest(
    context: FavoriteDetailContext(
      record: FavoriteThreadCacheRecord(
        tid: tid,
        favid: 'fav-$tid',
        title: '收藏$tid',
        replies: 0,
        sourceTagName: tagName,
        contentKind: kind,
        firstSeenAt: DateTime(2026, 1, 1),
        lastSeenAt: DateTime(2026, 1, 1),
      ),
      detail: ThreadDetailData(
        tid: tid,
        fid: fid,
        typeid: typeid,
        subject: '主题$tid',
        author: '作者',
        replies: 0,
        views: 1,
        currentPage: 1,
        perPage: 20,
        posts: const <ThreadPost>[],
      ),
      tagName: tagName,
      kind: kind,
    ),
    options: const FavoriteIngestOptions(),
  );
}

class _FakeComicIngestService implements ComicFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    upsertedTids.add(detail.tid);
    return 'yamibo:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _FakeNovelIngestService implements NovelFavoriteIngestService {
  final List<String> upsertedTids = <String>[];
  final List<String> removedWorkIds = <String>[];

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    upsertedTids.add(detail.tid);
    return 'novel:${detail.fid}:${detail.tid}';
  }

  @override
  Future<void> removeFromShelf({required String workId}) async {
    removedWorkIds.add(workId);
  }
}

class _RecordingComicRepository implements ComicRepository {
  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return ComicEpisodeRefreshResult(
      insertedCount: episodeLinks.length,
      updatedCount: 0,
      totalCount: episodeLinks.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _ThrowingRefreshService implements ComicEpisodeRefreshService {
  const _ThrowingRefreshService();

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    throw StateError('refresh failed');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('refresh failed');
  }
}

class _RecordingSearchQueue implements ComicSearchRefreshQueueEnqueuer {
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
        availableAt: DateTime(2026, 5, 16),
        createdAt: DateTime(2026, 5, 16),
        updatedAt: DateTime(2026, 5, 16),
      ),
      position: 1,
      estimatedDuration: const Duration(milliseconds: 10500),
      deduplicated: false,
    );
  }
}

class _RecordingCoverPromoter implements ComicFirstEpisodeCoverPromoter {
  @override
  Future<bool> promoteIfPossible({required String comicId}) async {
    return true;
  }
}

class _FakeDuplicateMergeRepository implements ComicDuplicateMergeRepository {
  _FakeDuplicateMergeRepository({
    required List<ComicDuplicateGroup> groups,
  }) : _groups = groups.toList(growable: true);

  final List<ComicDuplicateGroup> _groups;
  final List<String> mergeComicIds = <String>[];

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) async {
    if (comicId == null || comicId.trim().isEmpty) {
      return List<ComicDuplicateGroup>.unmodifiable(_groups);
    }
    mergeComicIds.add(comicId.trim());
    return _groups
        .where((group) => group.comicIds.contains(comicId.trim()))
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
      movedEpisodeCount: 1,
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
