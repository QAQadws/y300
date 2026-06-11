import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

abstract class ComposerDraftRepository {
  Future<ComposerDraftSnapshot?> loadDraft(ComposerDraftIdentity identity);

  Future<void> saveDraft(ComposerDraftSnapshot draft);

  Future<void> deleteDraft(ComposerDraftIdentity identity);

  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  });

  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  });
}

class ComposerDraftPruneResult {
  const ComposerDraftPruneResult({
    required this.removedCount,
    required this.keptCount,
  });

  final int removedCount;
  final int keptCount;
}
