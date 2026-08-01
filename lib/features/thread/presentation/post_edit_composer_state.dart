import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/thread/domain/models/post_edit_composer_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';

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
    this.nativeSupported = true,
    required super.message,
    required super.useSignature,
    required super.isSubmitting,
    required super.restoredDraft,
    required super.imageAttachments,
    required super.isUploadingImages,
    required super.imageUploadCurrent,
    required super.imageUploadTotal,
    required this.attachmentSession,
    this.webReturnVerificationState = PostEditWebReturnVerificationState.idle,
    this.pendingConflict,
    this.serverMutationPossible = false,
    this.lastAttachmentDeleteOutcome,
    this.attachmentVerificationUnconfirmed = false,
    this.submitState = PostEditSubmitState.idle,
    this.lastSubmitOutcome,
    this.submitBlocked = false,
    this.confirmedOverwriteIntent = false,
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
    bool nativeSupported = true,
    bool restoredDraft = false,
    PostEditConflictState? pendingConflict,
    List<ComposerImageAttachment> imageAttachments =
        const <ComposerImageAttachment>[],
    Set<String> deletedAidTombstones = const <String>{},
  }) {
    return PostEditComposerState(
      target: target,
      snapshot: snapshot,
      baselineMessage: snapshot.rawMessage,
      baselineFingerprint: snapshot.baselineFingerprint,
      nativeSupported: nativeSupported,
      message: message ?? snapshot.rawMessage,
      useSignature: useSignature,
      isSubmitting: false,
      restoredDraft: restoredDraft,
      imageAttachments: imageAttachments,
      isUploadingImages: false,
      imageUploadCurrent: 0,
      imageUploadTotal: 0,
      attachmentSession: PostEditAttachmentSession.fromImages(
        snapshot.existingImages,
        deletedAidTombstones: deletedAidTombstones,
      ),
      pendingConflict: pendingConflict,
    );
  }

  final PostEditTarget target;
  final PostEditFormSnapshot snapshot;
  final String baselineMessage;
  final String baselineFingerprint;
  final bool nativeSupported;
  final PostEditAttachmentSession attachmentSession;
  final PostEditWebReturnVerificationState webReturnVerificationState;
  final PostEditConflictState? pendingConflict;
  final bool serverMutationPossible;
  final PostEditAttachmentDeleteOutcome? lastAttachmentDeleteOutcome;
  final bool attachmentVerificationUnconfirmed;
  final PostEditSubmitState submitState;
  final PostEditSubmitResponseKind? lastSubmitOutcome;
  final bool submitBlocked;
  final bool confirmedOverwriteIntent;

  bool get isDirtyAgainstBaseline {
    return message != baselineMessage ||
        imageAttachments.isNotEmpty ||
        isUploadingImages ||
        pendingAttachmentAids.isNotEmpty ||
        pendingConflict != null ||
        attachmentSession.deletedAidTombstones.isNotEmpty;
  }

  /// Whether leaving should tell the thread page to refresh defensively.
  ///
  /// In-flight requests are included because cancelling the local listener
  /// cannot prove that the server did not finish the operation.
  bool get mayHaveServerMutationOnExit {
    return serverMutationPossible ||
        isUploadingImages ||
        isSubmitting ||
        pendingAttachmentAids.isNotEmpty ||
        attachmentSession.deletingAids.isNotEmpty ||
        submitState != PostEditSubmitState.idle ||
        pendingConflict != null ||
        webReturnVerificationState ==
            PostEditWebReturnVerificationState.verifying ||
        webReturnVerificationState ==
            PostEditWebReturnVerificationState.changedClean ||
        webReturnVerificationState ==
            PostEditWebReturnVerificationState.conflict ||
        webReturnVerificationState ==
            PostEditWebReturnVerificationState.unconfirmed;
  }

  bool get canSubmit {
    if (!nativeSupported ||
        !hasValidSubmitContract ||
        !isDirtyAgainstBaseline ||
        isSubmitting ||
        isUploadingImages ||
        pendingAttachmentAids.isNotEmpty ||
        attachmentSession.deletingAids.isNotEmpty ||
        attachmentVerificationUnconfirmed ||
        submitBlocked ||
        submitState == PostEditSubmitState.submitting ||
        submitState == PostEditSubmitState.verifying ||
        submitState == PostEditSubmitState.unconfirmed ||
        pendingConflict != null) {
      return false;
    }
    return true;
  }

  bool get hasValidSubmitContract {
    if (snapshot.target != target) {
      return false;
    }
    final values = snapshot.submitUri.queryParametersAll;
    return _singleQueryValue(values, 'mod')?.toLowerCase() == 'post' &&
        _singleQueryValue(values, 'action')?.toLowerCase() == 'edit' &&
        _singleQueryValue(values, 'editsubmit')?.toLowerCase() == 'yes';
  }

  String? _singleQueryValue(Map<String, List<String>> values, String name) {
    final entries = values[name];
    if (entries == null || entries.length != 1) {
      return null;
    }
    return entries.single;
  }

  PostEditComposerState copyWith({
    String? message,
    bool? useSignature,
    bool? isSubmitting,
    bool? restoredDraft,
    List<ComposerImageAttachment>? imageAttachments,
    bool? isUploadingImages,
    int? imageUploadCurrent,
    int? imageUploadTotal,
    PostEditAttachmentSession? attachmentSession,
    int? messageRevision,
    ComposerTextMutation? lastMessageMutation,
    List<String>? pendingAttachmentAids,
    ComposerPendingAttachmentNotice? pendingAttachmentNotice,
    ComposerFailure? failure,
    ComposerImageUploadFailure? imageUploadFailure,
    PostEditFormSnapshot? snapshot,
    String? baselineMessage,
    String? baselineFingerprint,
    bool? nativeSupported,
    PostEditWebReturnVerificationState? webReturnVerificationState,
    PostEditConflictState? pendingConflict,
    bool? serverMutationPossible,
    PostEditAttachmentDeleteOutcome? lastAttachmentDeleteOutcome,
    bool? attachmentVerificationUnconfirmed,
    PostEditSubmitState? submitState,
    PostEditSubmitResponseKind? lastSubmitOutcome,
    bool? submitBlocked,
    bool? confirmedOverwriteIntent,
    bool clearPendingConflict = false,
    bool clearFailure = false,
    bool clearImageUploadFailure = false,
    bool clearLastMessageMutation = false,
    bool clearPendingAttachmentNotice = false,
    bool clearLastAttachmentDeleteOutcome = false,
    bool clearLastSubmitOutcome = false,
  }) {
    final nextSnapshot = snapshot ?? this.snapshot;
    return PostEditComposerState(
      target: target,
      snapshot: nextSnapshot,
      baselineMessage: baselineMessage ?? this.baselineMessage,
      baselineFingerprint: baselineFingerprint ?? this.baselineFingerprint,
      nativeSupported: nativeSupported ?? this.nativeSupported,
      message: message ?? this.message,
      useSignature: useSignature ?? this.useSignature,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      restoredDraft: restoredDraft ?? this.restoredDraft,
      imageAttachments: imageAttachments ?? this.imageAttachments,
      isUploadingImages: isUploadingImages ?? this.isUploadingImages,
      imageUploadCurrent: imageUploadCurrent ?? this.imageUploadCurrent,
      imageUploadTotal: imageUploadTotal ?? this.imageUploadTotal,
      attachmentSession: attachmentSession ?? this.attachmentSession,
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
      lastAttachmentDeleteOutcome: clearLastAttachmentDeleteOutcome
          ? null
          : lastAttachmentDeleteOutcome ?? this.lastAttachmentDeleteOutcome,
      attachmentVerificationUnconfirmed:
          attachmentVerificationUnconfirmed ??
          this.attachmentVerificationUnconfirmed,
      submitState: submitState ?? this.submitState,
      lastSubmitOutcome: clearLastSubmitOutcome
          ? null
          : lastSubmitOutcome ?? this.lastSubmitOutcome,
      submitBlocked: submitBlocked ?? this.submitBlocked,
      confirmedOverwriteIntent:
          confirmedOverwriteIntent ?? this.confirmedOverwriteIntent,
    );
  }
}
