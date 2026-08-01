import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';

abstract interface class PostEditRepository {
  Future<ApiResult<PostEditPreparation>> loadForm(PostEditTarget target);

  Future<ApiResult<PostEditAttachmentDeleteResult>> deleteImage(
    PostEditAttachmentDeleteCommand command,
  );

  Future<ApiResult<PostEditSubmitResponse>> submit(
    PostEditSubmitPayload payload, {
    required PostEditTarget target,
  });
}
