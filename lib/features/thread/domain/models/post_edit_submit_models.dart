import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

enum PostEditSubmitResponseKind {
  confirmedSuccess,
  businessFailure,
  authenticationFailure,
  permissionFailure,
  formExpired,
  ambiguous,
  partialSuccess,
}

enum PostEditSubmitPayloadBuildFailure {
  targetMismatch,
  invalidSubmitUri,
  duplicateMessage,
  unsupportedControl,
  uploadInProgress,
  deletionInProgress,
}

final class PostEditSubmitCommand {
  const PostEditSubmitCommand({
    required this.target,
    required this.snapshot,
    required this.message,
    required this.imageAttachments,
    required this.attachmentSession,
    required this.now,
  });

  final PostEditTarget target;
  final PostEditFormSnapshot snapshot;
  final String message;
  final List<ComposerImageAttachment> imageAttachments;
  final PostEditAttachmentSession attachmentSession;
  final DateTime now;
}

final class PostEditSubmitPayload {
  PostEditSubmitPayload({
    required this.submitUri,
    required List<MapEntry<String, String>> fields,
    required List<String> danglingAids,
    required List<String> attachNewAids,
  }) : fields = List.unmodifiable(fields),
       danglingAids = List.unmodifiable(danglingAids),
       attachNewAids = List.unmodifiable(attachNewAids);

  final Uri submitUri;
  final List<MapEntry<String, String>> fields;
  final List<String> danglingAids;
  final List<String> attachNewAids;
}

final class PostEditSubmitPayloadBuildException implements Exception {
  const PostEditSubmitPayloadBuildException(this.failure);

  final PostEditSubmitPayloadBuildFailure failure;

  @override
  String toString() => 'PostEditSubmitPayloadBuildException($failure)';
}

final class PostEditSubmitResponse {
  const PostEditSubmitResponse({
    required this.kind,
    this.detail,
    this.redirectUri,
  });

  final PostEditSubmitResponseKind kind;
  final String? detail;
  final Uri? redirectUri;
}

final class PostEditSubmitVerification {
  const PostEditSubmitVerification({
    required this.kind,
    this.snapshot,
    this.detail,
  });

  final PostEditSubmitResponseKind kind;
  final PostEditFormSnapshot? snapshot;
  final String? detail;
}
