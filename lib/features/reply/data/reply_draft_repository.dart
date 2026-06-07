import 'package:y300/features/reply/domain/models/reply_models.dart';

abstract class ReplyDraftRepository {
  Future<ReplyDraftSnapshot?> loadDraft(ReplyDraftIdentity identity);

  Future<void> saveDraft(ReplyDraftSnapshot draft);

  Future<void> deleteDraft(ReplyDraftIdentity identity);

  Future<ReplyDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  });

  Future<List<ReplyDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  });
}

class ReplyDraftPruneResult {
  const ReplyDraftPruneResult({
    required this.removedCount,
    required this.keptCount,
  });

  final int removedCount;
  final int keptCount;
}
