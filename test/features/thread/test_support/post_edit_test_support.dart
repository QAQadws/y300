import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

PostEditTarget buildPostEditTarget({
  bool isFirstPost = false,
  String fid = '5',
  String tid = '557857',
  String pid = '41587383',
  int page = 1,
}) {
  return PostEditTarget(
    editUri: Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=$page&mobile=2',
    ),
    fid: fid,
    tid: tid,
    pid: pid,
    page: page,
    isFirstPost: isFirstPost,
  );
}

ThreadPostEditPreparation buildPostEditPreparation({
  PostEditTarget? target,
  bool isFirstPost = false,
  String subject = '标题',
  String message = '服务器正文',
  bool useSignature = true,
  String revision = 'revision-1',
  List<ThreadPostEditImageAttachment> existingImages =
      const <ThreadPostEditImageAttachment>[],
}) {
  final resolvedTarget =
      target ?? buildPostEditTarget(isFirstPost: isFirstPost);
  return ThreadPostEditPreparation(
    target: resolvedTarget.toClientTarget(),
    sourceUri: resolvedTarget.editUri,
    subject: isFirstPost ? subject : '',
    message: message,
    useSignature: useSignature,
    existingImages: existingImages,
    revision: revision,
    token: const TestThreadPostEditPreparationToken(),
  );
}

ThreadPostEditCapabilities buildPostEditCapabilities() {
  return ThreadPostEditCapabilities(
    values: DataCapabilitySet<ThreadPostEditCapability>.supported(
      ThreadPostEditCapability.values,
    ),
  );
}

final class TestThreadPostEditPreparationToken
    implements ThreadPostEditPreparationToken {
  const TestThreadPostEditPreparationToken();
}
