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

class ReplySubmissionResult {
  const ReplySubmissionResult({
    required this.message,
  });

  final String message;
}
