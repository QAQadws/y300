import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';

sealed class ComposerFailure {
  const ComposerFailure({this.detail});

  /// Diagnostic or server-provided detail. Presentation must sanitize it.
  final String? detail;
}

enum ComposerSubmissionFailureCode {
  authenticationRequired,
  credentialExpired,
  rateLimited,
  permissionDenied,
  typeRequired,
  subjectTooShort,
  subjectTooLong,
  contentTooShort,
  contentTooLong,
  targetUnavailable,
  threadClosed,
  captchaRequired,
  pollInvalid,
  pollOptionCountInvalid,
  pollFieldsInvalid,
  timeout,
  network,
  server,
  outcomeUnknown,
  unknown,
}

final class ComposerSubmissionFailure extends ComposerFailure {
  const ComposerSubmissionFailure({
    required this.code,
    required this.kind,
    super.detail,
  });

  final ComposerSubmissionFailureCode code;
  final ComposerKind kind;
}

enum ComposerValidationFailureCode {
  contentRequired,
  replyReferenceUnavailable,
  subjectRequired,
  bodyRequired,
  metadataLoading,
  metadataUnavailable,
  typeRequired,
  subjectTooLong,
  bodyTooLong,
  pollMissing,
  pollTooFewOptions,
  pollOptionTooLong,
  pollMultipleChoiceInvalid,
}

final class ComposerValidationFailure extends ComposerFailure {
  const ComposerValidationFailure({
    required this.code,
    this.limit,
    this.count,
    super.detail,
  });

  final ComposerValidationFailureCode code;
  final int? limit;
  final int? count;
}

enum ComposerOperationFailureCode {
  draftLoad,
  postingMetadataLoad,
  replyPreparation,
  unknown,
}

final class ComposerOperationFailure extends ComposerFailure {
  const ComposerOperationFailure({required this.code, super.detail});

  final ComposerOperationFailureCode code;
}

enum ComposerImageUploadFailureCode {
  pickerFailed,
  fileMissing,
  invalidFileType,
  extensionNotAllowed,
  permissionExpired,
  quotaExceeded,
  fileTooLarge,
  permissionDenied,
  invalidImage,
  saveFailed,
  fileNameRejected,
  dimensionsExceeded,
  outcomeUnknown,
  timeout,
  network,
  server,
  unknown,
}

final class ComposerImageUploadFailure {
  const ComposerImageUploadFailure({required this.code, this.detail});

  final ComposerImageUploadFailureCode code;

  /// Diagnostic-only detail. Presentation must sanitize it before display.
  final String? detail;
}

enum ComposerPendingAttachmentNoticeCode { readyToReinsert, selectionExpired }

final class ComposerPendingAttachmentNotice {
  const ComposerPendingAttachmentNotice({
    required this.code,
    required this.count,
  });

  final ComposerPendingAttachmentNoticeCode code;
  final int count;
}
