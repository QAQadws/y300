import 'package:y300/features/reply/domain/models/reply_models.dart';

enum ReplyComposerMode {
  source,
  preview,
}

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
    return ReplyDraftIdentity.thread(
      fid: target.fid,
      tid: target.tid,
    );
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

class ReplyComposerState {
  const ReplyComposerState({
    required this.target,
    required this.message,
    required this.useSignature,
    required this.isSubmitting,
    required this.mode,
    required this.isPreparing,
    required this.restoredDraft,
    required this.imageAttachments,
    required this.isUploadingImages,
    required this.imageUploadCurrent,
    required this.imageUploadTotal,
    this.preparation,
    this.preparationError,
    this.errorMessage,
    this.imageUploadError,
  });

  factory ReplyComposerState.initial({
    required ReplyTarget target,
    String message = '',
    bool useSignature = true,
    ReplyComposerMode mode = ReplyComposerMode.source,
    bool isPreparing = false,
    bool restoredDraft = false,
    List<ReplyImageAttachment> imageAttachments = const [],
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
      mode: mode,
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
  final String message;
  final bool useSignature;
  final bool isSubmitting;
  final ReplyComposerMode mode;
  final bool isPreparing;
  final bool restoredDraft;
  final List<ReplyImageAttachment> imageAttachments;
  final bool isUploadingImages;
  final int imageUploadCurrent;
  final int imageUploadTotal;
  final ReplyPreparation? preparation;
  final String? preparationError;
  final String? errorMessage;
  final String? imageUploadError;

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
    ReplyComposerMode? mode,
    bool? isPreparing,
    bool? restoredDraft,
    List<ReplyImageAttachment>? imageAttachments,
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
      mode: mode ?? this.mode,
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
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      imageUploadError:
          clearImageUploadError ? null : imageUploadError ?? this.imageUploadError,
    );
  }
}

class ReplyComposerResult {
  const ReplyComposerResult({
    required this.sent,
    required this.message,
  });

  const ReplyComposerResult.sent(String message)
      : this(sent: true, message: message);

  final bool sent;
  final String message;
}
