import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
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
    super.messageRevision,
    super.lastMessageMutation,
    super.pendingAttachmentAids,
    super.pendingAttachmentNotice,
    this.preparation,
    this.preparationFailure,
    super.failure,
    super.imageUploadFailure,
    super.draftAttachmentVerification,
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
    int messageRevision = 0,
    ComposerTextMutation? lastMessageMutation,
    List<String> pendingAttachmentAids = const <String>[],
    ComposerPendingAttachmentNotice? pendingAttachmentNotice,
    ThreadReplyPreparation? preparation,
    ComposerOperationFailure? preparationFailure,
    ComposerDraftAttachmentVerification draftAttachmentVerification =
        const ComposerDraftAttachmentVerification.notRequired(),
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
      messageRevision: messageRevision,
      lastMessageMutation: lastMessageMutation,
      pendingAttachmentAids: pendingAttachmentAids,
      pendingAttachmentNotice: pendingAttachmentNotice,
      preparation: preparation,
      preparationFailure: preparationFailure,
      draftAttachmentVerification: draftAttachmentVerification,
    );
  }

  final ReplyTarget target;
  final bool isPreparing;
  final ThreadReplyPreparation? preparation;
  final ComposerOperationFailure? preparationFailure;

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
    int? messageRevision,
    ComposerTextMutation? lastMessageMutation,
    List<String>? pendingAttachmentAids,
    ComposerPendingAttachmentNotice? pendingAttachmentNotice,
    ThreadReplyPreparation? preparation,
    ComposerOperationFailure? preparationFailure,
    ComposerFailure? failure,
    ComposerImageUploadFailure? imageUploadFailure,
    ComposerDraftAttachmentVerification? draftAttachmentVerification,
    bool clearPreparation = false,
    bool clearPreparationFailure = false,
    bool clearFailure = false,
    bool clearImageUploadFailure = false,
    bool clearLastMessageMutation = false,
    bool clearPendingAttachmentNotice = false,
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
      messageRevision: messageRevision ?? this.messageRevision,
      lastMessageMutation: clearLastMessageMutation
          ? null
          : lastMessageMutation ?? this.lastMessageMutation,
      pendingAttachmentAids:
          pendingAttachmentAids ?? this.pendingAttachmentAids,
      pendingAttachmentNotice: clearPendingAttachmentNotice
          ? null
          : pendingAttachmentNotice ?? this.pendingAttachmentNotice,
      preparation: clearPreparation ? null : preparation ?? this.preparation,
      preparationFailure: clearPreparationFailure
          ? null
          : preparationFailure ?? this.preparationFailure,
      failure: clearFailure ? null : failure ?? this.failure,
      imageUploadFailure: clearImageUploadFailure
          ? null
          : imageUploadFailure ?? this.imageUploadFailure,
      draftAttachmentVerification:
          draftAttachmentVerification ?? this.draftAttachmentVerification,
    );
  }
}

class ReplyComposerResult extends ComposerSubmitInvocationResult {
  const ReplyComposerResult({
    required super.sent,
    super.rawSuccessDetail,
    super.failure,
  });

  const ReplyComposerResult.sent({String? rawDetail})
    : this(sent: true, rawSuccessDetail: rawDetail);

  factory ReplyComposerResult.fromInvocation(
    ComposerSubmitInvocationResult invocation,
  ) {
    return ReplyComposerResult(
      sent: invocation.sent,
      rawSuccessDetail: invocation.rawSuccessDetail,
      failure: invocation.failure,
    );
  }
}
