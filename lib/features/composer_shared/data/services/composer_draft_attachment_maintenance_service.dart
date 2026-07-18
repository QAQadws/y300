import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';

abstract class ComposerDraftAttachmentMaintenanceService {
  Future<ComposerDraftAttachmentMaintenanceResult> maintain();
}

class ComposerDraftAttachmentMaintenanceResult {
  const ComposerDraftAttachmentMaintenanceResult({
    required this.scannedDraftCount,
    required this.sanitizedDraftCount,
    required this.deletedDraftCount,
    required this.removedAttachmentCount,
    required this.deletedCacheFileCount,
    required this.failedDraftCount,
  });

  final int scannedDraftCount;
  final int sanitizedDraftCount;
  final int deletedDraftCount;
  final int removedAttachmentCount;
  final int deletedCacheFileCount;
  final int failedDraftCount;
}

/// Runs the repository retention and attachment sanitation policy at startup.
class RepositoryComposerDraftAttachmentMaintenanceService
    implements ComposerDraftAttachmentMaintenanceService {
  const RepositoryComposerDraftAttachmentMaintenanceService({
    required ComposerDraftRepository repository,
  }) : _repository = repository;

  final ComposerDraftRepository _repository;

  @override
  Future<ComposerDraftAttachmentMaintenanceResult> maintain() async {
    try {
      final result = await _repository.pruneDrafts();
      return ComposerDraftAttachmentMaintenanceResult(
        scannedDraftCount: result.keptCount + result.removedCount,
        sanitizedDraftCount: result.sanitizedCount,
        deletedDraftCount: result.removedCount,
        removedAttachmentCount: result.removedAttachmentCount,
        deletedCacheFileCount: result.deletedCacheFileCount,
        failedDraftCount: result.failedCount,
      );
    } catch (_) {
      return const ComposerDraftAttachmentMaintenanceResult(
        scannedDraftCount: 0,
        sanitizedDraftCount: 0,
        deletedDraftCount: 0,
        removedAttachmentCount: 0,
        deletedCacheFileCount: 0,
        failedDraftCount: 1,
      );
    }
  }
}
