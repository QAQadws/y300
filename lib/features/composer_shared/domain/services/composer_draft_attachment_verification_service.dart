import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';

abstract interface class ComposerDraftAttachmentVerificationService {
  Future<ComposerDraftAttachmentVerificationResult> verify(
    ComposerDraftSnapshot draft,
  );
}
