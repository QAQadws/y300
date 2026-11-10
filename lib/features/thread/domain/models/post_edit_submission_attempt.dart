import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Exact local intent of one command, also used for explicit read-only proof.
final class PostEditSubmissionAttempt {
  PostEditSubmissionAttempt({
    required this.preparation,
    required this.subject,
    required this.message,
    required this.useSignature,
    required this.minimumReadAccess,
    required List<String> newImageAttachmentIds,
    required List<String> removedImageAttachmentIds,
  }) : newImageAttachmentIds = List.unmodifiable(newImageAttachmentIds),
       removedImageAttachmentIds = List.unmodifiable(removedImageAttachmentIds);

  final ThreadPostEditPreparation preparation;
  final String subject;
  final String message;
  final bool useSignature;
  final int? minimumReadAccess;
  final List<String> newImageAttachmentIds;
  final List<String> removedImageAttachmentIds;

  PostEditSubmissionAttempt withPreparation(ThreadPostEditPreparation value) =>
      PostEditSubmissionAttempt(
        preparation: value,
        subject: subject,
        message: message,
        useSignature: useSignature,
        minimumReadAccess: minimumReadAccess,
        newImageAttachmentIds: newImageAttachmentIds,
        removedImageAttachmentIds: removedImageAttachmentIds,
      );

  ThreadPostEditSubmission toSubmission() => ThreadPostEditSubmission(
    preparation: preparation,
    subject: subject,
    message: message,
    useSignature: useSignature,
    minimumReadAccess: minimumReadAccess == preparation.readAccess.currentValue
        ? null
        : minimumReadAccess,
    newImageAttachmentIds: newImageAttachmentIds,
    removedImageAttachmentIds: removedImageAttachmentIds,
  );
}
