/// 发帖目标的业务身份。
///
/// `fid` 由 WebView 拦截器或后续的 forum_display AppBar 入口提供；
/// `sourceUri` 仅作埋点 / 排错使用，不参与提交载荷；
/// `suggestedSubject` 留给未来"从某个内容生成发帖"的场景预填标题——
/// Phase 3 数据层不消费此字段。
class PostingTarget {
  const PostingTarget({
    required this.fid,
    this.sourceUri,
    this.suggestedSubject,
  });

  final String fid;
  final Uri? sourceUri;
  final String? suggestedSubject;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PostingTarget &&
        other.fid == fid &&
        other.sourceUri == sourceUri &&
        other.suggestedSubject == suggestedSubject;
  }

  @override
  int get hashCode => Object.hash(fid, sourceUri, suggestedSubject);
}
