import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_attach_bbcode_service.dart';
import 'package:y300/features/reply/domain/services/reply_image_attachment_expiry_policy.dart';

class ReplyDraftAttachmentSanitizationResult {
  const ReplyDraftAttachmentSanitizationResult({
    required this.message,
    required this.imageAttachments,
    required this.removedAttachments,
  });

  final String message;
  final List<ReplyImageAttachment> imageAttachments;
  final List<ReplyImageAttachment> removedAttachments;

  bool get changed => removedAttachments.isNotEmpty;
}

class ReplyDraftAttachmentSanitizer {
  const ReplyDraftAttachmentSanitizer({
    this.expiryPolicy = const ReplyImageAttachmentExpiryPolicy(),
    this.bbCodeService = const ReplyAttachBbCodeService(),
  });

  final ReplyImageAttachmentExpiryPolicy expiryPolicy;
  final ReplyAttachBbCodeService bbCodeService;

  ReplyDraftAttachmentSanitizationResult sanitize({
    required String message,
    required List<ReplyImageAttachment> imageAttachments,
    required DateTime now,
  }) {
    final kept = <ReplyImageAttachment>[];
    final removed = <ReplyImageAttachment>[];
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
    return ReplyDraftAttachmentSanitizationResult(
      message: bbCodeService.removeAttachCodes(message, removedAids),
      imageAttachments: kept,
      removedAttachments: removed,
    );
  }

  bool _isExpired(ReplyImageAttachment attachment, DateTime now) {
    if (attachment.status == ReplyImageAttachmentStatus.expired) {
      return true;
    }
    return expiryPolicy.isExpired(
      uploadedAt: attachment.uploadedAt,
      now: now,
    );
  }
}
