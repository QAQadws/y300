import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_draft_attachment_maintenance_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

void main() {
  test(
    'maintenance exposes repository sanitation and retention result',
    () async {
      final repository = _FakeDraftRepository(
        const ComposerDraftPruneResult(
          removedCount: 2,
          keptCount: 3,
          sanitizedCount: 1,
          removedAttachmentCount: 4,
          deletedCacheFileCount: 3,
          failedCount: 1,
        ),
      );
      final service = RepositoryComposerDraftAttachmentMaintenanceService(
        repository: repository,
      );

      final result = await service.maintain();

      expect(result.scannedDraftCount, 5);
      expect(result.deletedDraftCount, 2);
      expect(result.sanitizedDraftCount, 1);
      expect(result.removedAttachmentCount, 4);
      expect(result.deletedCacheFileCount, 3);
      expect(result.failedDraftCount, 1);
    },
  );
}

class _FakeDraftRepository implements ComposerDraftRepository {
  _FakeDraftRepository(this.result);

  final ComposerDraftPruneResult result;

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async => result;

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {}

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async => const <ComposerDraftSnapshot>[];

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async => null;

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {}
}
