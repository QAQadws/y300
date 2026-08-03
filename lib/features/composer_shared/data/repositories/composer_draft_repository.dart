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

/// Optional capability implemented by repositories that can reconcile an aid
/// across persisted drafts.
abstract interface class ComposerDraftAttachmentInvalidator {
  Future<ComposerDraftAttachmentInvalidationResult> invalidateAttachmentAids({
    required Set<String> aids,
    ComposerDraftIdentity? identity,
  });
}

extension ComposerDraftAttachmentInvalidation on ComposerDraftRepository {
  /// Removes server-invalid attachment metadata while preserving all message
  /// BBCode. Repositories without the optional capability remain source-
  /// compatible and simply report that nothing changed.
  Future<ComposerDraftAttachmentInvalidationResult> invalidateAttachmentAids({
    required Set<String> aids,
    ComposerDraftIdentity? identity,
  }) {
    final repository = this;
    if (repository is ComposerDraftAttachmentInvalidator) {
      return (repository as ComposerDraftAttachmentInvalidator)
          .invalidateAttachmentAids(aids: aids, identity: identity);
    }
    return Future<ComposerDraftAttachmentInvalidationResult>.value(
      const ComposerDraftAttachmentInvalidationResult(),
    );
  }
}

class ComposerDraftAttachmentInvalidationResult {
  const ComposerDraftAttachmentInvalidationResult({
    this.affectedDraftCount = 0,
    this.removedAttachmentCount = 0,
    this.deletedCacheFileCount = 0,
    this.updatedDraft,
  });

  final int affectedDraftCount;
  final int removedAttachmentCount;
  final int deletedCacheFileCount;
  final ComposerDraftSnapshot? updatedDraft;
}

class ComposerDraftPruneResult {
  const ComposerDraftPruneResult({
    required this.removedCount,
    required this.keptCount,
    this.sanitizedCount = 0,
    this.removedAttachmentCount = 0,
    this.deletedCacheFileCount = 0,
    this.failedCount = 0,
  });

  final int removedCount;
  final int keptCount;
  final int sanitizedCount;
  final int removedAttachmentCount;
  final int deletedCacheFileCount;
  final int failedCount;
}
