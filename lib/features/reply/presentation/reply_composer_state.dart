import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';

class ReplyComposerArgs {
  const ReplyComposerArgs({
    required this.target,
    this.title,
    this.replyFormUri,
  });

  final ReplyTarget target;
  final String? title;
  final Uri? replyFormUri;

  ReplyDraftIdentity get identity {
    final pid = target.pid;
    if (target.isPostReply && pid != null && pid.trim().isNotEmpty) {
      return ReplyDraftIdentity.post(
        fid: target.fid,
        tid: target.tid,
        repquote: pid,
      );
    }
    return ReplyDraftIdentity.thread(fid: target.fid, tid: target.tid);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ReplyComposerArgs &&
        other.target.kind == target.kind &&
        other.target.fid == target.fid &&
        other.target.tid == target.tid &&
        other.target.pid == target.pid &&
        other.target.sourceUri == target.sourceUri &&
        other.title == title &&
        other.replyFormUri == replyFormUri;
  }

  @override
  int get hashCode => Object.hash(
    target.kind,
    target.fid,
    target.tid,
    target.pid,
    target.sourceUri,
    title,
    replyFormUri,
  );
}

class ReplyComposerState extends ComposerStateBase {
  const ReplyComposerState({
    required this.target,
    required super.message,
    required super.useSignature,
    required super.isSubmitting,
    required this.isPreparing,
    required super.restoredDraft,
    required super.imageAttachments,
    required super.isUploadingImages,
    required super.imageUploadCurrent,
    required super.imageUploadTotal,
    this.preparation,
    this.preparationError,
    super.errorMessage,
    super.imageUploadError,
  });

  factory ReplyComposerState.initial({
    required ReplyTarget target,
    String message = '',
    bool useSignature = true,
    bool isPreparing = false,
    bool restoredDraft = false,
    List<ComposerImageAttachment> imageAttachments = const [],
    bool isUploadingImages = false,
    int imageUploadCurrent = 0,
    int imageUploadTotal = 0,
    ReplyPreparation? preparation,
    String? preparationError,
  }) {
    return ReplyComposerState(
      target: target,
      message: message,
      useSignature: useSignature,
      isSubmitting: false,
      isPreparing: isPreparing,
      restoredDraft: restoredDraft,
      imageAttachments: imageAttachments,
      isUploadingImages: isUploadingImages,
      imageUploadCurrent: imageUploadCurrent,
      imageUploadTotal: imageUploadTotal,
      preparation: preparation,
      preparationError: preparationError,
    );
  }

  final ReplyTarget target;
  final bool isPreparing;
  final ReplyPreparation? preparation;
  final String? preparationError;

  bool get canPickImages => !isSubmitting && !isPreparing && !isUploadingImages;

  bool get canSubmit {
    if (message.trim().isEmpty || isSubmitting || isPreparing) {
      return false;
    }
    if (target.isPostReply && preparation == null) {
      return false;
    }
    return true;
  }

  ReplyComposerState copyWith({
    String? message,
    bool? useSignature,
    bool? isSubmitting,
    bool? isPreparing,
    bool? restoredDraft,
    List<ComposerImageAttachment>? imageAttachments,
    bool? isUploadingImages,
    int? imageUploadCurrent,
    int? imageUploadTotal,
    ReplyPreparation? preparation,
    String? preparationError,
    String? errorMessage,
    String? imageUploadError,
    bool clearPreparation = false,
    bool clearPreparationError = false,
    bool clearErrorMessage = false,
    bool clearImageUploadError = false,
  }) {
    return ReplyComposerState(
      target: target,
      message: message ?? this.message,
      useSignature: useSignature ?? this.useSignature,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isPreparing: isPreparing ?? this.isPreparing,
      restoredDraft: restoredDraft ?? this.restoredDraft,
      imageAttachments: imageAttachments ?? this.imageAttachments,
      isUploadingImages: isUploadingImages ?? this.isUploadingImages,
      imageUploadCurrent: imageUploadCurrent ?? this.imageUploadCurrent,
      imageUploadTotal: imageUploadTotal ?? this.imageUploadTotal,
      preparation: clearPreparation ? null : preparation ?? this.preparation,
      preparationError: clearPreparationError
          ? null
          : preparationError ?? this.preparationError,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      imageUploadError: clearImageUploadError
          ? null
          : imageUploadError ?? this.imageUploadError,
    );
  }
}

class ReplyComposerResult extends ComposerSubmitInvocationResult {
  const ReplyComposerResult({required super.sent, required super.message});

  const ReplyComposerResult.sent(String message)
    : this(sent: true, message: message);

  factory ReplyComposerResult.fromInvocation(
    ComposerSubmitInvocationResult invocation,
  ) {
    return ReplyComposerResult(
      sent: invocation.sent,
      message: invocation.message,
    );
  }
}
