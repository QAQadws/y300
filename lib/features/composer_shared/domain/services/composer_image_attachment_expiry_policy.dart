/// 已上传附件本地副本的过期策略。
///
/// 远端 aid 是否有效由 Discuz unused-image catalog 决定；时间策略只清理
/// composer 自己持有的本地副本，不能删除附件元数据或用户正文。
class ComposerImageAttachmentExpiryPolicy {
  const ComposerImageAttachmentExpiryPolicy({
    this.maxAge = const Duration(days: 14),
  });

  final Duration maxAge;

  bool isExpired({required DateTime? uploadedAt, required DateTime now}) {
    if (uploadedAt == null) {
      return false;
    }
    return !uploadedAt.add(maxAge).isAfter(now);
  }
}
