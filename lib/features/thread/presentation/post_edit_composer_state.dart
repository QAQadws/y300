import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final class PostEditComposerArgs {
  PostEditComposerArgs({required this.preparation})
    : assert(preparation.isNativeSupported && preparation.snapshot != null);

  final PostEditPreparation preparation;

  PostEditTarget get target => preparation.target;
  PostEditFormSnapshot get snapshot => preparation.snapshot!;
}

final class PostEditComposerState extends ComposerStateBase {
  const PostEditComposerState({
    required this.target,
    required this.snapshot,
    required this.baselineMessage,
    required this.baselineFingerprint,
    required super.message,
    required super.useSignature,
    required super.isSubmitting,
    required super.restoredDraft,
    required super.imageAttachments,
    required super.isUploadingImages,
    required super.imageUploadCurrent,
    required super.imageUploadTotal,
    this.webReturnVerificationState = PostEditWebReturnVerificationState.idle,
    this.pendingConflict,
    this.serverMutationPossible = false,
    super.messageRevision,
    super.lastMessageMutation,
    super.pendingAttachmentAids,
    super.pendingAttachmentNotice,
    super.failure,
    super.imageUploadFailure,
  });

  factory PostEditComposerState.initial({
    required PostEditTarget target,
    required PostEditFormSnapshot snapshot,
    String? message,
    bool useSignature = true,
    bool restoredDraft = false,
    PostEditDraftConflict? pendingConflict,
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
  }) {
    return PostEditComposerState(
      target: target,
      snapshot: snapshot,
      baselineMessage: snapshot.rawMessage,
      baselineFingerprint: snapshot.baselineFingerprint,
      message: message ?? snapshot.rawMessage,
      useSignature: useSignature,
      isSubmitting: false,
      restoredDraft: restoredDraft,
      imageAttachments: imageAttachments,
      isUploadingImages: false,
      imageUploadCurrent: 0,
      imageUploadTotal: 0,
      pendingConflict: pendingConflict,
    );
  }

  final PostEditTarget target;
  final PostEditFormSnapshot snapshot;
  final String baselineMessage;
  final String baselineFingerprint;
  final PostEditWebReturnVerificationState webReturnVerificationState;
  final PostEditDraftConflict? pendingConflict;
  final bool serverMutationPossible;

  bool get isDirtyAgainstBaseline {
    return message != baselineMessage ||
        imageAttachments.isNotEmpty ||
        isUploadingImages ||
        pendingAttachmentAids.isNotEmpty ||
        pendingConflict != null;
  }

  bool get canSubmit => false;

  PostEditComposerState copyWith({
    String? message,
    bool? useSignature,
    bool? isSubmitting,
    bool? restoredDraft,
    List<ComposerImageAttachment>? imageAttachments,
    bool? isUploadingImages,
    int? imageUploadCurrent,
    int? imageUploadTotal,
    int? messageRevision,
    ComposerTextMutation? lastMessageMutation,
    List<String>? pendingAttachmentAids,
    ComposerPendingAttachmentNotice? pendingAttachmentNotice,
    ComposerFailure? failure,
    ComposerImageUploadFailure? imageUploadFailure,
    PostEditFormSnapshot? snapshot,
    String? baselineMessage,
    String? baselineFingerprint,
    PostEditWebReturnVerificationState? webReturnVerificationState,
    PostEditDraftConflict? pendingConflict,
    bool? serverMutationPossible,
    bool clearPendingConflict = false,
    bool clearFailure = false,
    bool clearImageUploadFailure = false,
    bool clearLastMessageMutation = false,
    bool clearPendingAttachmentNotice = false,
  }) {
    final nextSnapshot = snapshot ?? this.snapshot;
    return PostEditComposerState(
      target: target,
      snapshot: nextSnapshot,
      baselineMessage: baselineMessage ?? this.baselineMessage,
      baselineFingerprint: baselineFingerprint ?? this.baselineFingerprint,
      message: message ?? this.message,
      useSignature: useSignature ?? this.useSignature,
      isSubmitting: isSubmitting ?? this.isSubmitting,
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
      failure: clearFailure ? null : failure ?? this.failure,
      imageUploadFailure: clearImageUploadFailure
          ? null
          : imageUploadFailure ?? this.imageUploadFailure,
      webReturnVerificationState:
          webReturnVerificationState ?? this.webReturnVerificationState,
      pendingConflict: clearPendingConflict
          ? null
          : pendingConflict ?? this.pendingConflict,
      serverMutationPossible:
          serverMutationPossible ?? this.serverMutationPossible,
    );
  }
}
