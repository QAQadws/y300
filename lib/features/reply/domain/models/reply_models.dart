import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

export 'package:y300/features/composer_shared/domain/models/sticker_models.dart'
    show StickerGroup, StickerItem;

/// reply 模块仍然需要的"业务身份/提交载荷"类型保留在这里。
///
/// 通用模型（图片附件、表情、草稿身份、上传权限等）已经迁移到
/// `features/composer_shared/domain/models`，这里通过 typedef 把旧类型名
/// 映射到新位置，避免一次性改动所有调用方。Phase 2 会推进到子类化时再
/// 把这些 typedef 收敛掉。

// ── 通用模型的 re-export（来自 composer_shared，供 reply 旧代码继续调用）──
typedef ReplyImageAttachment = ComposerImageAttachment;
typedef ReplyImageAttachmentStatus = ComposerImageAttachmentStatus;
typedef ReplyAttachRemain = ComposerAttachRemain;
typedef ReplyImageUploadPermission = ComposerImageUploadPermission;
typedef ReplyPickedImage = ComposerPickedImage;
typedef ReplyLocalImageFile = ComposerLocalImageFile;
typedef ReplyImageUploadResponse = ComposerImageUploadResponse;
typedef ReplyUploadedImage = ComposerUploadedImage;
typedef ReplyDraftIdentity = ComposerDraftIdentity;
typedef ReplyDraftSnapshot = ComposerDraftSnapshot;

// ── reply 专属模型 ─────────────────────────────────────────────────────────

enum ReplyTargetKind { thread, post }

class ReplyTarget {
  const ReplyTarget.thread({
    required this.fid,
    required this.tid,
    this.sourceUri,
  }) : kind = ReplyTargetKind.thread,
       pid = null;

  const ReplyTarget.post({
    required this.fid,
    required this.tid,
    required this.pid,
    this.sourceUri,
  }) : kind = ReplyTargetKind.post;

  final ReplyTargetKind kind;
  final String fid;
  final String tid;
  final String? pid;
  final Uri? sourceUri;

  bool get isThreadReply => kind == ReplyTargetKind.thread;
  bool get isPostReply => kind == ReplyTargetKind.post;
}
