import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 草稿身份。Phase 1 复用既有 reply 草稿的命名规则
/// （`thread:fid:tid` / `post:fid:tid:repquote`），
/// 后续阶段会扩展为统一的 `ComposerScope`，目前先保持线协议兼容。
class ComposerDraftIdentity {
  const ComposerDraftIdentity.thread({
    required this.fid,
    required this.tid,
  }) : repquote = null;

  const ComposerDraftIdentity.post({
    required this.fid,
    required this.tid,
    required this.repquote,
  });

  final String fid;
  final String tid;
  final String? repquote;

  bool get isThreadReply => repquote == null || repquote!.trim().isEmpty;
  bool get isPostReply => !isThreadReply;

  String get storageKey {
    if (isThreadReply) {
      return 'thread:$fid:$tid';
    }
    return 'post:$fid:$tid:$repquote';
  }
}

class ComposerDraftSnapshot {
  const ComposerDraftSnapshot({
    required this.identity,
    required this.message,
    required this.useSignature,
    required this.updatedAt,
    this.imageAttachments = const <ComposerImageAttachment>[],
  });

  final ComposerDraftIdentity identity;
  final String message;
  final bool useSignature;
  final DateTime updatedAt;
  final List<ComposerImageAttachment> imageAttachments;

  bool get isEmpty => message.trim().isEmpty && imageAttachments.isEmpty;
}
