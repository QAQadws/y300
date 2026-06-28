import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

abstract class ReplyRepository {
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  });

  Future<ApiResult<ReplyPreparation>> preparePostReply({
    required Uri replyFormUri,
  });
}
