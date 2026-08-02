import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';
import 'package:y300/features/thread/domain/services/post_edit_message_canonicalizer.dart';

final class PostEditSubmitVerificationService {
  const PostEditSubmitVerificationService({
    this.messageCanonicalizer = const PostEditMessageCanonicalizer(),
  });

  final PostEditMessageCanonicalizer messageCanonicalizer;

  PostEditSubmitVerification verify({
    required PostEditFormSnapshot before,
    required PostEditFormSnapshot after,
    required String submittedSubject,
    required String submittedMessage,
    required Iterable<String> attachNewAids,
  }) {
    if (after.baselineFingerprint == before.baselineFingerprint) {
      return const PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.ambiguous,
        detail: 'baseline_unchanged',
      );
    }
    if (messageCanonicalizer.canonicalize(after.rawMessage) !=
        messageCanonicalizer.canonicalize(submittedMessage)) {
      return PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.ambiguous,
        snapshot: after,
        detail: 'message_mismatch',
      );
    }
    if (after.originalSubject.trim() != submittedSubject.trim()) {
      return PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.ambiguous,
        snapshot: after,
        detail: 'subject_mismatch',
      );
    }

    final returnedAids = {for (final image in after.existingImages) image.aid};
    final missingAids = attachNewAids.where(
      (aid) => !returnedAids.contains(aid),
    );
    if (missingAids.isNotEmpty) {
      return PostEditSubmitVerification(
        kind: PostEditSubmitResponseKind.partialSuccess,
        snapshot: after,
        detail: 'attachment_association_unconfirmed',
      );
    }
    return PostEditSubmitVerification(
      kind: PostEditSubmitResponseKind.confirmedSuccess,
      snapshot: after,
    );
  }
}
