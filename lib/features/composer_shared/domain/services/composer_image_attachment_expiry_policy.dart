/// 已上传附件的过期策略：上传后超过一定时长视为过期。
///
/// 站点端会在一段时间内把临时附件清理掉；本地草稿即便仍然引用 aid
/// 也已经无意义。`maxAge` 默认 24 小时与现有 reply 行为保持一致。
class ComposerImageAttachmentExpiryPolicy {
  const ComposerImageAttachmentExpiryPolicy({
    this.maxAge = const Duration(hours: 24),
  });

  final Duration maxAge;

  bool isExpired({
    required DateTime? uploadedAt,
    required DateTime now,
  }) {
    if (uploadedAt == null) {
      return false;
    }
    return !uploadedAt.add(maxAge).isAfter(now);
  }
}
