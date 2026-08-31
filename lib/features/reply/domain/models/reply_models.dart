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
