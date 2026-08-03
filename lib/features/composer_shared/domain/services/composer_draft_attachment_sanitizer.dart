import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_expiry_policy.dart';

class ComposerDraftAttachmentSanitizationResult {
  const ComposerDraftAttachmentSanitizationResult({
    required this.message,
    required this.imageAttachments,
    required this.removedAttachments,
    required this.expiredCacheAttachments,
  });

  final String message;
  final List<ComposerImageAttachment> imageAttachments;
  final List<ComposerImageAttachment> removedAttachments;
  final List<ComposerImageAttachment> expiredCacheAttachments;

  List<ComposerImageAttachment> get cacheCleanupAttachments =>
      <ComposerImageAttachment>[
        ...removedAttachments,
        ...expiredCacheAttachments,
      ];

  bool get changed =>
      removedAttachments.isNotEmpty || expiredCacheAttachments.isNotEmpty;
}

/// 草稿层的本地缓存清洗。
///
/// 14 天到期只清空受管缓存引用并保留远端 aid；旧版本显式标记为 expired
/// 且仍带 aid 的附件会迁回 uploaded 状态，以便联网校验后继续预览和提交。
/// 只有无法对应远端附件的无 aid 旧记录才会被移除，正文 BBCode 始终不改写。
class ComposerDraftAttachmentSanitizer {
  const ComposerDraftAttachmentSanitizer({
    this.expiryPolicy = const ComposerImageAttachmentExpiryPolicy(),
  });

  final ComposerImageAttachmentExpiryPolicy expiryPolicy;

  ComposerDraftAttachmentSanitizationResult sanitize({
    required String message,
    required List<ComposerImageAttachment> imageAttachments,
    required DateTime now,
  }) {
    final kept = <ComposerImageAttachment>[];
    final removed = <ComposerImageAttachment>[];
    final expiredCaches = <ComposerImageAttachment>[];
    for (final attachment in imageAttachments) {
      if (attachment.status == ComposerImageAttachmentStatus.expired) {
        if (!attachment.hasAid) {
          removed.add(attachment);
          continue;
        }
        expiredCaches.add(attachment);
        kept.add(
          attachment.copyWith(
            status: ComposerImageAttachmentStatus.uploaded,
            cachePath: null,
          ),
        );
        continue;
      }
      final cachePath = attachment.cachePath?.trim();
      if (cachePath != null &&
          cachePath.isNotEmpty &&
          expiryPolicy.isExpired(uploadedAt: attachment.uploadedAt, now: now)) {
        expiredCaches.add(attachment);
        kept.add(attachment.copyWith(cachePath: null));
        continue;
      }
      kept.add(attachment);
    }

    return ComposerDraftAttachmentSanitizationResult(
      message: message,
      imageAttachments: kept,
      removedAttachments: removed,
      expiredCacheAttachments: expiredCaches,
    );
  }
}
