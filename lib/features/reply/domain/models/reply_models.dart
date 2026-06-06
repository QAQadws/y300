enum ReplyTargetKind {
  thread,
  post,
}

class ReplyTarget {
  const ReplyTarget.thread({
    required this.fid,
    required this.tid,
    this.sourceUri,
  })  : kind = ReplyTargetKind.thread,
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

class ReplyReference {
  const ReplyReference({
    this.formHash,
    this.noticeAuthor,
    this.noticeTrimStr,
    this.noticeAuthorMsg,
    this.repPid,
    this.repPost,
    this.rawQuotePreview,
  });

  final String? formHash;
  final String? noticeAuthor;
  final String? noticeTrimStr;
  final String? noticeAuthorMsg;
  final String? repPid;
  final String? repPost;
  final String? rawQuotePreview;

  bool get hasServerQuote =>
      noticeTrimStr != null && noticeTrimStr!.trim().isNotEmpty;
}

class ReplyDraft {
  const ReplyDraft({
    required this.fid,
    required this.tid,
    required this.message,
    this.useSignature = true,
    this.repPid,
    this.repPost,
    this.noticeAuthor,
    this.noticeTrimStr,
    this.noticeAuthorMsg,
  });

  final String fid;
  final String tid;
  final String message;
  final bool useSignature;
  final String? repPid;
  final String? repPost;
  final String? noticeAuthor;
  final String? noticeTrimStr;
  final String? noticeAuthorMsg;
}

class ReplyPreparation {
  const ReplyPreparation({
    required this.target,
    required this.reference,
    this.subject,
  });

  final ReplyTarget target;
  final ReplyReference reference;
  final String? subject;
}

class ReplyDraftIdentity {
  const ReplyDraftIdentity.thread({
    required this.fid,
    required this.tid,
  }) : repquote = null;

  const ReplyDraftIdentity.post({
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

class ReplyDraftSnapshot {
  const ReplyDraftSnapshot({
    required this.identity,
    required this.message,
    required this.useSignature,
    required this.updatedAt,
  });

  final ReplyDraftIdentity identity;
  final String message;
  final bool useSignature;
  final DateTime updatedAt;

  bool get isEmpty => message.trim().isEmpty;
}

class ReplySubmissionResult {
  const ReplySubmissionResult({
    required this.message,
  });

  final String message;
}

class StickerGroup {
  const StickerGroup({
    required this.id,
    required this.title,
    required this.stickers,
  });

  final String id;
  final String title;
  final List<StickerItem> stickers;
}

class StickerItem {
  const StickerItem({
    required this.code,
    required this.assetPath,
    required this.rawCodePattern,
  });

  final String code;
  final String assetPath;
  final String rawCodePattern;
}
