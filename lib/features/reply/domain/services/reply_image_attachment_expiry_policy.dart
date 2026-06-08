class ReplyImageAttachmentExpiryPolicy {
  const ReplyImageAttachmentExpiryPolicy({
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
