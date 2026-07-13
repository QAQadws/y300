import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/data/services/default_novel_chapter_update_service.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_recovery_service.dart';

void main() {
  test(
    'ready novel updates incrementally from its persisted checkpoint',
    () async {
      final sourceRepository = _MemorySourceStateRepository(
        _sourceState(
          hydrationState: NovelChapterHydrationState.ready,
          publisherId: '406769',
          checkpointPage: 3,
        ),
      );
      final syncService = _RecordingChapterSyncService();
      final service = _service(
        sourceRepository: sourceRepository,
        syncService: syncService,
      );

      await service.update('novel:55:521519');

      expect(syncService.request?.mode, NovelChapterSyncMode.incremental);
      expect(syncService.request?.tid, '521519');
      expect(syncService.request?.publisherId, '406769');
      expect(syncService.request?.checkpoint?.lastCompletedAuthorPage, 3);
    },
  );

  test('non-ready novel retries initial full without a checkpoint', () async {
    final sourceRepository = _MemorySourceStateRepository(
      _sourceState(
        hydrationState: NovelChapterHydrationState.failed,
        publisherId: '406769',
      ),
    );
    final syncService = _RecordingChapterSyncService();
    final service = _service(
      sourceRepository: sourceRepository,
      syncService: syncService,
    );

    await service.update('novel:55:521519');

    expect(syncService.request?.mode, NovelChapterSyncMode.initialFull);
    expect(syncService.request?.checkpoint, isNull);
  });

  test('missing publisher is recovered before initial full update', () async {
    final sourceRepository = _MemorySourceStateRepository(
      _sourceState(hydrationState: NovelChapterHydrationState.metadataOnly),
    );
    final recoveryService = _RecordingRecoveryService(() {
      sourceRepository.state = _sourceState(
        hydrationState: NovelChapterHydrationState.metadataOnly,
        publisherId: '406769',
      );
    });
    final syncService = _RecordingChapterSyncService();
    final service = _service(
      sourceRepository: sourceRepository,
      syncService: syncService,
      recoveryService: recoveryService,
    );

    await service.update('novel:55:521519');

    expect(recoveryService.novelIds, <String>['novel:55:521519']);
    expect(syncService.request?.publisherId, '406769');
    expect(syncService.request?.mode, NovelChapterSyncMode.initialFull);
  });

  test('ready novel without checkpoint fails closed', () async {
    final sourceRepository = _MemorySourceStateRepository(
      _sourceState(
        hydrationState: NovelChapterHydrationState.ready,
        publisherId: '406769',
      ),
    );
    final syncService = _RecordingChapterSyncService();
    final service = _service(
      sourceRepository: sourceRepository,
      syncService: syncService,
    );

    await expectLater(
      service.update('novel:55:521519'),
      throwsA(isA<StateError>()),
    );

    expect(syncService.request, isNull);
  });
}

DefaultNovelChapterUpdateService _service({
  required _MemorySourceStateRepository sourceRepository,
  required _RecordingChapterSyncService syncService,
  _RecordingRecoveryService? recoveryService,
}) {
  return DefaultNovelChapterUpdateService(
    repository: _DetailNovelRepository(),
    sourceStateRepository: sourceRepository,
    syncService: syncService,
    metadataRecoveryService:
        recoveryService ?? _RecordingRecoveryService(() {}),
  );
}

class _DetailNovelRepository implements NovelRepository {
  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '521519',
      sourceFid: '55',
      title: '测试小说',
      updatedAt: DateTime(2026, 7, 13),
      episodeCount: 3,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySourceStateRepository implements NovelSourceStateRepository {
  _MemorySourceStateRepository(this.state);

  NovelSourceState? state;

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    return state;
  }

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {}

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {}

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {}
}

class _RecordingChapterSyncService implements NovelChapterSyncService {
  NovelChapterSyncRequest? request;

  @override
  bool hasActiveRun(String novelId) => false;

  @override
  Future<NovelChapterSyncResult> synchronize(
    NovelChapterSyncRequest request,
  ) async {
    this.request = request;
    return NovelChapterSyncResult(
      mode: request.mode,
      fetchedPages: 1,
      insertedCount: 0,
      updatedCount: 1,
      totalCount: 3,
      checkpoint:
          request.checkpoint ??
          NovelChapterSyncCheckpoint(
            novelId: request.novelId,
            publisherId: request.publisherId,
            lastCompletedAuthorPage: 1,
            lastSeenPid: '5001',
            completedAt: DateTime(2026, 7, 14),
          ),
    );
  }

  @override
  Stream<NovelChapterSyncProgress> watchProgress(String novelId) {
    return const Stream<NovelChapterSyncProgress>.empty();
  }
}

class _RecordingRecoveryService implements NovelSourceMetadataRecoveryService {
  _RecordingRecoveryService(this.onRecover);

  final void Function() onRecover;
  final List<String> novelIds = <String>[];

  @override
  Future<NovelSourceMetadata> recover(String novelId) async {
    novelIds.add(novelId);
    onRecover();
    return NovelSourceMetadata(
      novelId: novelId,
      tid: '521519',
      fid: '55',
      subject: '测试小说',
      publisherName: 'Author',
      publisherId: '406769',
      firstPostPid: '1',
      catalogEntries: const <NovelSourceCatalogEntry>[],
      sourceIntro: null,
      coverImageUrl: null,
      sourceApiVersion: 4,
      ingestedAt: DateTime(2026, 7, 14),
    );
  }
}

NovelSourceState _sourceState({
  required NovelChapterHydrationState hydrationState,
  String? publisherId,
  int? checkpointPage,
}) {
  return NovelSourceState(
    novelId: 'novel:55:521519',
    publisherId: publisherId,
    publisherName: 'Author',
    firstPostPid: '1',
    sourceIntro: null,
    catalogEntries: const <NovelSourceCatalogEntry>[],
    metadataSourceVersion: 4,
    hydrationState: hydrationState,
    metadataIngestedAt: DateTime(2026, 7, 13),
    chaptersHydratedAt: checkpointPage == null ? null : DateTime(2026, 7, 13),
    lastCompletedAuthorPage: checkpointPage ?? 0,
    lastSeenPid: checkpointPage == null ? null : '5003',
    lastSyncAt: checkpointPage == null ? null : DateTime(2026, 7, 13),
    lastError: null,
  );
}
