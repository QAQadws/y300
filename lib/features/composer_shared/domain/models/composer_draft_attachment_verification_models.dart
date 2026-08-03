import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_unused_image_models.dart';

enum ComposerDraftAttachmentVerificationStatus { notRequired, verified, failed }

final class ComposerDraftAttachmentVerification {
  const ComposerDraftAttachmentVerification._({
    required this.status,
    this.verifiedImagesByAid = const <String, ComposerUnusedImage>{},
    this.checkedAids = const <String>{},
    this.unverifiedAids = const <String>{},
    this.invalidAidCount = 0,
    this.failureDetail,
  });

  const ComposerDraftAttachmentVerification.notRequired()
    : this._(status: ComposerDraftAttachmentVerificationStatus.notRequired);

  ComposerDraftAttachmentVerification.verified({
    required Map<String, ComposerUnusedImage> imagesByAid,
    required int invalidAidCount,
    Set<String>? checkedAids,
  }) : this._(
         status: ComposerDraftAttachmentVerificationStatus.verified,
         verifiedImagesByAid: Map<String, ComposerUnusedImage>.unmodifiable(
           imagesByAid,
         ),
         checkedAids: Set<String>.unmodifiable(checkedAids ?? imagesByAid.keys),
         invalidAidCount: invalidAidCount,
       );

  ComposerDraftAttachmentVerification.failed({
    required Set<String> unverifiedAids,
    String? failureDetail,
  }) : this._(
         status: ComposerDraftAttachmentVerificationStatus.failed,
         unverifiedAids: Set<String>.unmodifiable(unverifiedAids),
         failureDetail: failureDetail,
       );

  final ComposerDraftAttachmentVerificationStatus status;
  final Map<String, ComposerUnusedImage> verifiedImagesByAid;
  final Set<String> checkedAids;
  final Set<String> unverifiedAids;
  final int invalidAidCount;
  final String? failureDetail;

  bool get failed => status == ComposerDraftAttachmentVerificationStatus.failed;
  bool get verified =>
      status == ComposerDraftAttachmentVerificationStatus.verified;
}

final class ComposerDraftAttachmentVerificationResult {
  const ComposerDraftAttachmentVerificationResult({
    required this.draft,
    required this.verification,
  });

  final ComposerDraftSnapshot draft;
  final ComposerDraftAttachmentVerification verification;
}
