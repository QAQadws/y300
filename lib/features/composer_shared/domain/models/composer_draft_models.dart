import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';

/// 草稿身份。
///
/// reply/posting/edit 草稿共用同一份持久化层，
/// 避免后续再做"发帖与回复草稿存储分裂"的迁移工作。
class ComposerDraftIdentity {
  const ComposerDraftIdentity._({
    required this.kind,
    required this.fid,
    this.tid,
    this.repquote,
  });

  const ComposerDraftIdentity.thread({required String fid, required String tid})
    : this._(kind: ComposerDraftKind.threadReply, fid: fid, tid: tid);

  const ComposerDraftIdentity.post({
    required String fid,
    required String tid,
    required String repquote,
  }) : this._(
         kind: ComposerDraftKind.postReply,
         fid: fid,
         tid: tid,
         repquote: repquote,
       );

  /// 发帖草稿身份；`tid` / `repquote` 都为空。同一个 fid 上同时只保留一份发帖草稿。
  const ComposerDraftIdentity.newThread({required String fid})
    : this._(kind: ComposerDraftKind.newThread, fid: fid);

  const ComposerDraftIdentity.postEdit({
    required String fid,
    required String tid,
    required String pid,
  }) : this._(
         kind: ComposerDraftKind.postEdit,
         fid: fid,
         tid: tid,
         repquote: pid,
       );

  final ComposerDraftKind kind;
  final String fid;
  final String? tid;
  final String? repquote;

  bool get isThreadReply => kind == ComposerDraftKind.threadReply;
  bool get isPostReply => kind == ComposerDraftKind.postReply;
  bool get isNewThread => kind == ComposerDraftKind.newThread;
  bool get isPostEdit => kind == ComposerDraftKind.postEdit;

  String get storageKey {
    switch (kind) {
      case ComposerDraftKind.threadReply:
        return 'thread:$fid:$tid';
      case ComposerDraftKind.postReply:
        return 'post:$fid:$tid:$repquote';
      case ComposerDraftKind.newThread:
        return 'newthread:$fid';
      case ComposerDraftKind.postEdit:
        return 'edit:$fid:$tid:$repquote';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ComposerDraftIdentity &&
        other.kind == kind &&
        other.fid == fid &&
        other.tid == tid &&
        other.repquote == repquote;
  }

  @override
  int get hashCode => Object.hash(kind, fid, tid, repquote);
}

enum ComposerDraftKind { threadReply, postReply, newThread, postEdit }

/// 编辑器持久化的"通用草稿快照"。
///
/// Phase 4 在原 reply 字段的基础上扩展了 [subject] 与 [extras]：
/// - [subject]：发帖标题；reply 永远为空字符串。
/// - [extras]：发帖类目、可选项等小型 KV，预留给"投票 / 悬赏"等扩展。
///   存储时与 reply 字段写在同一个 JSON 中，老版本 reply 草稿读出时自动回退到 `''`/`{}`，
///   保证升级不丢失既有草稿。
class ComposerDraftSnapshot {
  const ComposerDraftSnapshot({
    required this.identity,
    required this.message,
    required this.useSignature,
    required this.updatedAt,
    this.subject = '',
    this.extras = const <String, String>{},
    this.imageAttachments = const <ComposerImageAttachment>[],
  });

  final ComposerDraftIdentity identity;
  final String message;
  final bool useSignature;
  final DateTime updatedAt;
  final String subject;
  final Map<String, String> extras;
  final List<ComposerImageAttachment> imageAttachments;

  /// 草稿是否"实质为空"：标题、正文、附件和业务 extras 都为空，
  /// 才可以被存储层删除。编辑草稿的附件 tombstone 保存在 extras 中。
  bool get isEmpty {
    return subject.trim().isEmpty &&
        message.trim().isEmpty &&
        imageAttachments.isEmpty &&
        extras.isEmpty;
  }
}
