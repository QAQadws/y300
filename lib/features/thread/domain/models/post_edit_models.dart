import 'post_edit_failure_models.dart';

export 'post_edit_failure_models.dart';

enum PostEditFormControlKind { hidden, text, textarea, checkbox, radio, select }

final class PostEditTarget {
  const PostEditTarget({
    required this.editUri,
    required this.fid,
    required this.tid,
    required this.pid,
    required this.page,
    required this.isFirstPost,
  });

  final Uri editUri;
  final String fid;
  final String tid;
  final String pid;
  final int page;
  final bool isFirstPost;

  @override
  bool operator ==(Object other) {
    return other is PostEditTarget &&
        other.editUri == editUri &&
        other.fid == fid &&
        other.tid == tid &&
        other.pid == pid &&
        other.page == page &&
        other.isFirstPost == isFirstPost;
  }

  @override
  int get hashCode => Object.hash(editUri, fid, tid, pid, page, isFirstPost);
}

final class PostEditTargetParseResult {
  const PostEditTargetParseResult.success(PostEditTarget target)
    : target = target,
      failure = null;

  const PostEditTargetParseResult.failure(PostEditTargetParseFailure failure)
    : target = null,
      failure = failure;

  final PostEditTarget? target;
  final PostEditTargetParseFailure? failure;

  bool get isSuccess => target != null;
}

final class PostEditFormField {
  const PostEditFormField({
    required this.name,
    required this.value,
    required this.controlKind,
  });

  final String name;
  final String value;
  final PostEditFormControlKind controlKind;
}

final class PostEditExistingImage {
  const PostEditExistingImage({
    required this.aid,
    required this.imageUri,
    required this.isAssociated,
    this.description = '',
    this.fileName,
  });

  final String aid;
  final Uri imageUri;
  final bool isAssociated;
  final String description;
  final String? fileName;
}

final class PostEditRegularAttachment {
  const PostEditRegularAttachment({required this.aid, this.fileName});

  final String aid;
  final String? fileName;
}

final class PostEditFormStructureEvidence {
  PostEditFormStructureEvidence({
    required List<String> allNamedControlNamesInDomOrder,
    this.hasExternalFormOwnerControls = false,
    this.hasUnsupportedControlType = false,
    this.hasRegularAttachments = false,
    this.hasSpecialEditorMarker = false,
    this.hasThreadSortMarker = false,
    this.hasPluginMarker = false,
    this.hasDestructiveField = false,
    this.hasAuditMarker = false,
  }) : allNamedControlNamesInDomOrder = List.unmodifiable(
         allNamedControlNamesInDomOrder,
       );

  final List<String> allNamedControlNamesInDomOrder;
  final bool hasExternalFormOwnerControls;
  final bool hasUnsupportedControlType;
  final bool hasRegularAttachments;
  final bool hasSpecialEditorMarker;
  final bool hasThreadSortMarker;
  final bool hasPluginMarker;
  final bool hasDestructiveField;
  final bool hasAuditMarker;
}

final class PostEditFormSnapshot {
  PostEditFormSnapshot({
    required this.target,
    required this.sourceUri,
    required this.submitUri,
    required this.formHash,
    required this.postTime,
    required this.rawMessage,
    required this.originalSubject,
    required List<PostEditFormField> successfulControls,
    required List<PostEditExistingImage> existingImages,
    required this.structureEvidence,
    required this.baselineFingerprint,
    List<PostEditRegularAttachment> regularAttachments =
        const <PostEditRegularAttachment>[],
  }) : successfulControls = List.unmodifiable(successfulControls),
       existingImages = List.unmodifiable(existingImages),
       regularAttachments = List.unmodifiable(regularAttachments);

  final PostEditTarget target;
  final Uri sourceUri;
  final Uri submitUri;
  final String formHash;
  final String postTime;
  final String rawMessage;
  final String originalSubject;
  final List<PostEditFormField> successfulControls;
  final List<PostEditExistingImage> existingImages;
  final List<PostEditRegularAttachment> regularAttachments;
  final PostEditFormStructureEvidence structureEvidence;
  final String baselineFingerprint;
}

sealed class PostEditNativeSupportDecision {
  const PostEditNativeSupportDecision();
}

final class PostEditNativeSupported extends PostEditNativeSupportDecision {
  const PostEditNativeSupported({required this.profileVersion});

  final int profileVersion;
}

final class PostEditWebViewOnly extends PostEditNativeSupportDecision {
  const PostEditWebViewOnly({required this.reason});

  final PostEditFallbackReason reason;
}

final class PostEditFormParseResult {
  const PostEditFormParseResult.success(PostEditFormSnapshot snapshot)
    : snapshot = snapshot,
      failure = null;

  const PostEditFormParseResult.failure(PostEditFormParseFailureReason failure)
    : snapshot = null,
      failure = failure;

  final PostEditFormSnapshot? snapshot;
  final PostEditFormParseFailureReason? failure;

  bool get isSuccess => snapshot != null;
}

final class PostEditPreparation {
  const PostEditPreparation({
    required this.target,
    required this.decision,
    this.snapshot,
  });

  final PostEditTarget target;
  final PostEditNativeSupportDecision decision;
  final PostEditFormSnapshot? snapshot;

  bool get isNativeSupported => decision is PostEditNativeSupported;
  bool get isWebViewOnly => decision is PostEditWebViewOnly;
}
