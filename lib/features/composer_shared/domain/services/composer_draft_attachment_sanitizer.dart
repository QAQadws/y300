import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_service.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_expiry_policy.dart';

class ComposerDraftAttachmentSanitizationResult {
  const ComposerDraftAttachmentSanitizationResult({
    required this.message,
    required this.imageAttachments,
    required this.removedAttachments,
  });

  final String message;
  final List<ComposerImageAttachment> imageAttachments;
  final List<ComposerImageAttachment> removedAttachments;

  bool get changed => removedAttachments.isNotEmpty;
}

/// 草稿层的附件清洗：把过期 / 已被服务端回收的附件从 message 与列表中清除，
/// 同时返回被移除的项，供存储层联动删除本地缓存文件。
class ComposerDraftAttachmentSanitizer {
  const ComposerDraftAttachmentSanitizer({
    this.expiryPolicy = const ComposerImageAttachmentExpiryPolicy(),
    this.bbCodeService = const ComposerAttachBbCodeService(),
  });

  final ComposerImageAttachmentExpiryPolicy expiryPolicy;
  final ComposerAttachBbCodeService bbCodeService;

  ComposerDraftAttachmentSanitizationResult sanitize({
    required String message,
    required List<ComposerImageAttachment> imageAttachments,
    required DateTime now,
  }) {
    final kept = <ComposerImageAttachment>[];
    final removed = <ComposerImageAttachment>[];
    for (final attachment in imageAttachments) {
      if (_isExpired(attachment, now)) {
        removed.add(attachment);
      } else {
        kept.add(attachment);
      }
    }

    final removedAids = removed
        .map((attachment) => attachment.aid)
        .whereType<String>()
        .where((aid) => aid.trim().isNotEmpty);
    return ComposerDraftAttachmentSanitizationResult(
      message: bbCodeService.removeAttachCodes(message, removedAids),
      imageAttachments: kept,
      removedAttachments: removed,
    );
  }

  bool _isExpired(ComposerImageAttachment attachment, DateTime now) {
    if (attachment.status == ComposerImageAttachmentStatus.expired) {
      return true;
    }
    return expiryPolicy.isExpired(uploadedAt: attachment.uploadedAt, now: now);
  }
}
