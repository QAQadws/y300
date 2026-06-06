import 'package:y300/features/reply/domain/models/reply_models.dart';

abstract class ReplyDraftRepository {
  Future<ReplyDraftSnapshot?> loadDraft(ReplyDraftIdentity identity);

  Future<void> saveDraft(ReplyDraftSnapshot draft);

  Future<void> deleteDraft(ReplyDraftIdentity identity);

  Future<List<ReplyDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  });
}
