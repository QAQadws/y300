import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_recovery_service.dart';

class DefaultNovelChapterUpdateService implements NovelChapterUpdateService {
  const DefaultNovelChapterUpdateService({
    required NovelRepository repository,
    required NovelSourceStateRepository sourceStateRepository,
    required NovelChapterSyncService syncService,
    required NovelSourceMetadataRecoveryService metadataRecoveryService,
  }) : _repository = repository,
       _sourceStateRepository = sourceStateRepository,
       _syncService = syncService,
       _metadataRecoveryService = metadataRecoveryService;

  final NovelRepository _repository;
  final NovelSourceStateRepository _sourceStateRepository;
  final NovelChapterSyncService _syncService;
  final NovelSourceMetadataRecoveryService _metadataRecoveryService;

  @override
  Future<NovelChapterSyncResult> update(String novelId) async {
    final normalizedNovelId = novelId.trim();
    if (normalizedNovelId.isEmpty) {
      throw ArgumentError.value(novelId, 'novelId', 'must not be empty');
    }

    var sourceState = await _sourceStateRepository.getSourceState(
      novelId: normalizedNovelId,
    );
    if (sourceState == null) {
      throw const NovelChapterSyncException(
        NovelChapterSyncFailureCode.missingSourceState,
      );
    }
    var publisherId = sourceState.publisherId?.trim() ?? '';
    if (publisherId.isEmpty) {
      await _metadataRecoveryService.recover(normalizedNovelId);
      sourceState = await _sourceStateRepository.getSourceState(
        novelId: normalizedNovelId,
      );
      publisherId = sourceState?.publisherId?.trim() ?? '';
    }
    if (sourceState == null || publisherId.isEmpty) {
      throw const NovelChapterSyncException(
        NovelChapterSyncFailureCode.missingPublisherId,
      );
    }

    final detail = await _repository.getDetail(novelId: normalizedNovelId);
    final tid = detail?.sourceTid.trim() ?? '';
    if (tid.isEmpty) {
      throw const NovelChapterSyncException(
        NovelChapterSyncFailureCode.missingSourceTid,
      );
    }

    final isIncremental =
        sourceState.hydrationState == NovelChapterHydrationState.ready;
    final checkpoint = isIncremental ? sourceState.checkpoint : null;
    if (isIncremental && checkpoint == null) {
      throw const NovelChapterSyncException(
        NovelChapterSyncFailureCode.missingCheckpoint,
      );
    }
    return _syncService.synchronize(
      NovelChapterSyncRequest(
        novelId: normalizedNovelId,
        tid: tid,
        publisherId: publisherId,
        mode: isIncremental
            ? NovelChapterSyncMode.incremental
            : NovelChapterSyncMode.initialFull,
        checkpoint: checkpoint,
      ),
    );
  }
}
