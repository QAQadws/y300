import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_attach_bbcode_grammar.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_attachment_expiry_policy.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final class PostEditAttachmentSubmissionProjection {
  PostEditAttachmentSubmissionProjection({
    required List<String> danglingAids,
    required List<String> newAttachmentAids,
  }) : danglingAids = List.unmodifiable(danglingAids),
       newAttachmentAids = List.unmodifiable(newAttachmentAids);

  final List<String> danglingAids;
  final List<String> newAttachmentAids;
}

/// Maps App-owned editor attachments to source-neutral package identities.
final class PostEditSubmissionMapper {
  const PostEditSubmissionMapper({
    this.expiryPolicy = const ComposerImageAttachmentExpiryPolicy(),
  });

  final ComposerImageAttachmentExpiryPolicy expiryPolicy;
  static const _grammar = ComposerAttachBbCodeGrammar();

  PostEditAttachmentSubmissionProjection map({
    required String message,
    required List<ComposerImageAttachment> localAttachments,
    required PostEditAttachmentSession attachmentSession,
    required DateTime now,
  }) {
    final localByAid = <String, ComposerImageAttachment>{
      for (final attachment in localAttachments)
        if (attachment.aid?.trim().isNotEmpty == true)
          attachment.aid!.trim(): attachment,
    };
    final existingAids = attachmentSession.existingImagesByAid.keys.toSet();
    final referenced = <String>[];
    final seen = <String>{};
    final dangling = <String>[];
    for (final token in _grammar.scan(message)) {
      final aid = token.aid.trim();
      if (!seen.add(aid)) continue;
      referenced.add(aid);
      final local = localByAid[aid];
      final localUsable =
          local != null &&
          local.status == ComposerImageAttachmentStatus.uploaded &&
          !expiryPolicy.isExpired(uploadedAt: local.uploadedAt, now: now);
      final existingUsable = existingAids.contains(aid);
      if (attachmentSession.deletedAidTombstones.contains(aid) ||
          (!localUsable && !existingUsable)) {
        dangling.add(aid);
      }
    }
    final newAids = <String>[
      for (final aid in referenced)
        if (!existingAids.contains(aid) &&
            !attachmentSession.deletedAidTombstones.contains(aid) &&
            localByAid[aid]?.status == ComposerImageAttachmentStatus.uploaded &&
            !expiryPolicy.isExpired(
              uploadedAt: localByAid[aid]!.uploadedAt,
              now: now,
            ))
          aid,
    ];
    return PostEditAttachmentSubmissionProjection(
      danglingAids: dangling,
      newAttachmentAids: newAids,
    );
  }
}
