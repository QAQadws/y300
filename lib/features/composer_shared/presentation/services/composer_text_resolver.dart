import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/sticker_models.dart';
import 'package:y300/features/composer_shared/presentation/services/composer_error_summary.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/composer_bbcode_command.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_transient_feedback.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class ComposerTextResolver {
  static String bbCodeMenuCommand(
    AppLocalizations l10n,
    ComposerBbCodeMenuCommandKind kind,
  ) {
    return switch (kind) {
      ComposerBbCodeMenuCommandKind.quote => l10n.composerQuote,
      ComposerBbCodeMenuCommandKind.fontSize => l10n.composerFontSize,
    };
  }

  static String failure(AppLocalizations l10n, ComposerFailure failure) {
    return switch (failure) {
      ComposerSubmissionFailure value => submissionFailure(l10n, value),
      ComposerValidationFailure value => validationFailure(l10n, value),
      ComposerOperationFailure value => operationFailure(l10n, value),
    };
  }

  static String submissionFailure(
    AppLocalizations l10n,
    ComposerSubmissionFailure failure,
  ) {
    final kind = failure.kind.name;
    return switch (failure.code) {
      ComposerSubmissionFailureCode.authenticationRequired =>
        l10n.composerAuthenticationRequired,
      ComposerSubmissionFailureCode.credentialExpired =>
        l10n.composerCredentialExpired(kind),
      ComposerSubmissionFailureCode.rateLimited => l10n.composerRateLimited(
        kind,
      ),
      ComposerSubmissionFailureCode.permissionDenied =>
        l10n.composerPermissionDenied(kind),
      ComposerSubmissionFailureCode.typeRequired =>
        l10n.composerSubmissionTypeRequired,
      ComposerSubmissionFailureCode.subjectTooShort =>
        l10n.composerSubmissionSubjectTooShort,
      ComposerSubmissionFailureCode.subjectTooLong =>
        l10n.composerSubmissionSubjectTooLong,
      ComposerSubmissionFailureCode.contentTooShort =>
        l10n.composerSubmissionContentTooShort(kind),
      ComposerSubmissionFailureCode.contentTooLong =>
        l10n.composerSubmissionContentTooLong(kind),
      ComposerSubmissionFailureCode.targetUnavailable =>
        l10n.composerSubmissionTargetUnavailable(kind),
      ComposerSubmissionFailureCode.threadClosed =>
        l10n.composerSubmissionThreadClosed,
      ComposerSubmissionFailureCode.captchaRequired =>
        l10n.composerCaptchaRequired,
      ComposerSubmissionFailureCode.pollInvalid => l10n.composerPollInvalid,
      ComposerSubmissionFailureCode.pollOptionCountInvalid =>
        l10n.composerPollOptionCountInvalid,
      ComposerSubmissionFailureCode.pollFieldsInvalid =>
        l10n.composerPollFieldsInvalid,
      ComposerSubmissionFailureCode.timeout => l10n.composerNetworkTimeout,
      ComposerSubmissionFailureCode.network => l10n.composerNetworkFailure,
      ComposerSubmissionFailureCode.server => l10n.composerServerFailure,
      ComposerSubmissionFailureCode.outcomeUnknown =>
        l10n.composerOutcomeUnknown(kind),
      ComposerSubmissionFailureCode.unknown =>
        ComposerErrorSummary.sanitize(failure.detail) ??
            l10n.composerUnknownFailure(kind),
    };
  }

  static String validationFailure(
    AppLocalizations l10n,
    ComposerValidationFailure failure,
  ) {
    return switch (failure.code) {
      ComposerValidationFailureCode.contentRequired =>
        l10n.replyContentRequired,
      ComposerValidationFailureCode.replyReferenceUnavailable =>
        l10n.replyReferenceUnavailable,
      ComposerValidationFailureCode.subjectRequired =>
        l10n.postingSubjectRequired,
      ComposerValidationFailureCode.bodyRequired => l10n.postingBodyRequired,
      ComposerValidationFailureCode.metadataLoading =>
        l10n.postingFormStillLoading,
      ComposerValidationFailureCode.metadataUnavailable =>
        l10n.postingFormLoadFailed(_detailOrUnknown(l10n, failure.detail)),
      ComposerValidationFailureCode.typeRequired =>
        l10n.composerSubmissionTypeRequired,
      ComposerValidationFailureCode.subjectTooLong =>
        l10n.postingSubjectTooLong(failure.limit ?? 0),
      ComposerValidationFailureCode.bodyTooLong => l10n.postingBodyTooLong(
        failure.limit ?? 0,
      ),
      ComposerValidationFailureCode.pollMissing => l10n.postingPollMissing,
      ComposerValidationFailureCode.pollTooFewOptions =>
        l10n.postingPollTooFewOptions(failure.limit ?? 0),
      ComposerValidationFailureCode.pollOptionTooLong =>
        l10n.postingPollOptionTooLong(failure.limit ?? 0),
      ComposerValidationFailureCode.pollMultipleChoiceInvalid =>
        l10n.postingPollMultipleInvalid(failure.limit ?? 2),
    };
  }

  static String operationFailure(
    AppLocalizations l10n,
    ComposerOperationFailure failure,
  ) {
    final detail = _detailOrUnknown(l10n, failure.detail);
    return switch (failure.code) {
      ComposerOperationFailureCode.draftLoad => l10n.composerLoadDraftFailed(
        detail,
      ),
      ComposerOperationFailureCode.postingMetadataLoad =>
        l10n.postingFormLoadFailed(detail),
      ComposerOperationFailureCode.replyPreparation =>
        l10n.replyPreparationFailed(detail),
      ComposerOperationFailureCode.unknown => detail,
    };
  }

  static String pendingAttachment(
    AppLocalizations l10n,
    ComposerPendingAttachmentNotice notice,
  ) {
    return switch (notice.code) {
      ComposerPendingAttachmentNoticeCode.readyToReinsert =>
        l10n.composerPendingAttachment(notice.count),
      ComposerPendingAttachmentNoticeCode.selectionExpired =>
        l10n.composerPendingAttachmentSelectionExpired,
    };
  }

  static String uploadFailure(
    AppLocalizations l10n,
    ComposerImageUploadFailure failure,
  ) {
    return switch (failure.code) {
      ComposerImageUploadFailureCode.pickerFailed =>
        l10n.composerImagePickerFailed,
      ComposerImageUploadFailureCode.fileMissing =>
        l10n.composerImageFileMissing,
      ComposerImageUploadFailureCode.invalidFileType =>
        l10n.composerImageInvalidFileType,
      ComposerImageUploadFailureCode.extensionNotAllowed =>
        l10n.composerImageExtensionNotAllowed,
      ComposerImageUploadFailureCode.permissionExpired =>
        l10n.composerImagePermissionExpired,
      ComposerImageUploadFailureCode.quotaExceeded =>
        l10n.composerImageQuotaExceeded,
      ComposerImageUploadFailureCode.fileTooLarge =>
        l10n.composerImageFileTooLarge,
      ComposerImageUploadFailureCode.permissionDenied =>
        l10n.composerImagePermissionDenied,
      ComposerImageUploadFailureCode.invalidImage =>
        l10n.composerImageInvalidContent,
      ComposerImageUploadFailureCode.saveFailed => l10n.composerImageSaveFailed,
      ComposerImageUploadFailureCode.fileNameRejected =>
        l10n.composerImageFileNameRejected,
      ComposerImageUploadFailureCode.dimensionsExceeded =>
        l10n.composerImageDimensionsExceeded,
      ComposerImageUploadFailureCode.outcomeUnknown =>
        l10n.composerImageUploadOutcomeUnknown,
      ComposerImageUploadFailureCode.timeout => l10n.composerImageUploadTimeout,
      ComposerImageUploadFailureCode.network => l10n.composerImageUploadNetwork,
      ComposerImageUploadFailureCode.server => l10n.composerImageUploadServer,
      ComposerImageUploadFailureCode.unknown =>
        ComposerErrorSummary.sanitize(failure.detail) ??
            l10n.composerImageUploadUnknown,
    };
  }

  static String uploadFeedback(
    AppLocalizations l10n,
    ComposerUploadFeedback feedback,
  ) {
    return switch (feedback.type) {
      ComposerUploadFeedbackType.uploaded => l10n.composerImageUploaded(
        feedback.fileName ?? '',
      ),
      ComposerUploadFeedbackType.failed => _uploadFailedFeedback(
        l10n,
        feedback,
      ),
      ComposerUploadFeedbackType.batchFailure => uploadFailure(
        l10n,
        feedback.failure ??
            const ComposerImageUploadFailure(
              code: ComposerImageUploadFailureCode.unknown,
            ),
      ),
    };
  }

  static String submitSuccess(
    AppLocalizations l10n,
    ComposerKind kind,
    String? rawDetail,
  ) {
    final detail = ComposerErrorSummary.sanitize(rawDetail);
    return switch ((kind, detail)) {
      (ComposerKind.newThread, final String value) =>
        l10n.postingSubmitSuccessWithDetail(value),
      (ComposerKind.newThread, null) => l10n.postingSubmitSuccess,
      (ComposerKind.reply, final String value) =>
        l10n.replySubmitSuccessWithDetail(value),
      (ComposerKind.reply, null) => l10n.replySubmitSuccess,
      (ComposerKind.postEdit, _) => l10n.postEditNativeSubmitUnavailable,
    };
  }

  static String stickerGroupTitle(AppLocalizations l10n, StickerGroup group) {
    if (group.id == 'all') {
      return l10n.composerStickerAllGroup;
    }
    if (group.id == 'default' && group.title.trim() == '默认表情') {
      return l10n.composerStickerDefaultGroup;
    }
    return group.title;
  }

  static String _uploadFailedFeedback(
    AppLocalizations l10n,
    ComposerUploadFeedback feedback,
  ) {
    final failure = feedback.failure;
    if (failure == null ||
        failure.code == ComposerImageUploadFailureCode.unknown) {
      final reason = ComposerErrorSummary.sanitize(failure?.detail);
      if (reason != null) {
        return l10n.composerImageUploadFailedWithReason(
          feedback.fileName ?? '',
          reason,
        );
      }
    }
    return l10n.composerImageUploadFailed(feedback.fileName ?? '');
  }

  static String _detailOrUnknown(AppLocalizations l10n, Object? detail) {
    return ComposerErrorSummary.sanitize(detail) ??
        l10n.composerUnknownFailure('other');
  }
}
