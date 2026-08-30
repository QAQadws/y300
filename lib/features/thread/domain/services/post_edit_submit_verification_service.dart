import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_message_canonicalizer.dart';

final class PostEditSubmitVerification {
  const PostEditSubmitVerification({required this.kind, this.detail});

  final PostEditSubmitResponseKind kind;
  final String? detail;
}

/// App-side verification used only when the user explicitly retries a readback.
final class PostEditSubmitVerificationService {
  const PostEditSubmitVerificationService({
    this.messageCanonicalizer = const PostEditMessageCanonicalizer(),
  });

  final PostEditMessageCanonicalizer messageCanonicalizer;

  PostEditSubmitVerification verify({
    required ThreadPostEditPreparation before,
    required ThreadPostEditPreparation after,
    required String submittedSubject,
    required String submittedMessage,
    required Iterable<String> attachNewAids,
  }) {
    if (after.revision == before.revision) {
      return const PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.ambiguous,
        detail: 'baseline_unchanged',
      );
    }
    if (messageCanonicalizer.canonicalize(after.message) !=
        messageCanonicalizer.canonicalize(submittedMessage)) {
      return const PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.ambiguous,
        detail: 'message_mismatch',
      );
    }
    if (after.subject.trim() != submittedSubject.trim()) {
      return const PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.ambiguous,
        detail: 'subject_mismatch',
      );
    }
    final returnedAids = {for (final image in after.existingImages) image.aid};
    if (attachNewAids.any((aid) => !returnedAids.contains(aid))) {
      return const PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.partialSuccess,
        detail: 'attachment_association_unconfirmed',
      );
    }
    return const PostEditSubmitVerification(
      kind: PostEditSubmitResponseKind.confirmedSuccess,
    );
  }
}
