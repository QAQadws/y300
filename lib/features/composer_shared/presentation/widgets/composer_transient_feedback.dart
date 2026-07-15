import 'package:flutter/material.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

List<ComposerImageAttachment> visibleComposerImageAttachments(
  List<ComposerImageAttachment> attachments,
) {
  return [
    for (final attachment in attachments)
      if (attachment.status != ComposerImageAttachmentStatus.uploaded)
        attachment,
  ];
}

Set<String> uploadedComposerImageAttachmentIds(
  List<ComposerImageAttachment> attachments,
) {
  return {
    for (final attachment in attachments)
      if (attachment.status == ComposerImageAttachmentStatus.uploaded)
        attachment.localId,
  };
}

void showComposerSnackBar(BuildContext context, String message) {
  showTransientSnackBar(context, message);
}
