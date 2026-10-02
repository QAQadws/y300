/// Transient journal images and the editor's dedicated smiley catalog.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';
import 'forum_image_attachments.dart';
import 'user_blog_operations.dart';

/// Upload choices proved by the journal's complete editor form.
final class UserBlogImageUploadLimits {
  /// Creates image limits without exposing the upload hash.
  const UserBlogImageUploadLimits({
    required this.extensionRules,
    this.maximumBytes,
  });

  /// Enabled image extensions and any per-extension limits.
  final List<ForumImageAttachmentExtensionRule> extensionRules;

  /// Maximum bytes per image, or null when no limit was advertised.
  final int? maximumBytes;
}

/// One image from the journal editor's separate smiley catalog.
final class UserBlogSmiley {
  /// Creates a source-provided ordinal and image reference.
  const UserBlogSmiley({required this.index, required this.imageUri});

  /// Ordinal within this catalog, starting at one.
  final int index;

  /// Absolute smiley resource URI.
  final Uri imageUri;
}

/// Opaque ownership proof for an uploaded journal image; never persist it.
abstract interface class UserBlogUploadedImageToken {}

/// Confirmed album image, distinct from a forum attachment ID.
final class UserBlogUploadedImage {
  /// Creates a confirmed image receipt.
  const UserBlogUploadedImage({
    required this.picId,
    required this.imageUri,
    required this.originalImageUri,
    required this.token,
  });

  /// Positive album picture identity.
  final String picId;

  /// Image reference to insert; Discuz requires the full-size image for binding.
  final Uri imageUri;

  /// Full-size image reference, equal to [imageUri] for Discuz journals.
  final Uri originalImageUri;

  /// Actor, target, and adapter-bound proof used when saving the journal.
  final UserBlogUploadedImageToken token;
}

/// One local image uploaded against an already prepared journal form.
final class UserBlogImageUploadSubmission {
  /// Reuses the complete form and the shared streamed content abstraction.
  const UserBlogImageUploadSubmission({
    required this.preparation,
    required this.actorUserId,
    required this.content,
    this.cancellation,
    this.onProgress,
  });

  /// Prepared journal whose opaque ticket proves upload credentials.
  final UserBlogEditorPreparation preparation;

  /// Current signed-in actor, rechecked before and after sending.
  final String actorUserId;

  /// Replay-safe local image bytes.
  final ForumImageAttachmentContent content;

  /// Cooperative cancellation.
  final ForumRequestCancellation? cancellation;

  /// Normalized progress within zero and one.
  final void Function(double progress)? onProgress;
}

/// Optional journal media capability, separate from forum attachments.
abstract interface class UserBlogMediaOperations {
  /// Uploads once; uncertain outcomes must not be automatically replayed.
  Future<DataCommandResult<UserBlogUploadedImage>> uploadImage(
    UserBlogImageUploadSubmission submission,
  );
}

/// Persistable lookup hints; only a fresh actor-verified read creates proof.
final class UserBlogDraftImageReference {
  /// Creates an untrusted local reference to verify against the actor's album.
  const UserBlogDraftImageReference({
    required this.picId,
    required this.originalUri,
  });

  /// Positive album picture identity.
  final String picId;

  /// Original image address saved in the draft's HTML.
  final Uri originalUri;
}

/// Fresh binding proofs and references absent from a completely read album.
final class UserBlogDraftImageRestoration {
  /// Creates a verified restoration result.
  const UserBlogDraftImageRestoration({
    required this.images,
    required this.missingPicIds,
  });

  /// Verified images with current-session binding proofs.
  final List<UserBlogUploadedImage> images;

  /// Picture identities not found with their original addresses.
  final Set<String> missingPicIds;
}

/// Optional capability keeps existing media implementations source compatible.
abstract interface class UserBlogDraftImageRestorer {
  /// Reads the current actor's album without uploading or modifying images.
  Future<DataReadResult<UserBlogDraftImageRestoration, Object?>>
  restoreDraftImages(
    UserBlogEditorPreparation preparation, {
    required List<UserBlogDraftImageReference> images,
    ForumRequestCancellation? cancellation,
  });
}

/// Backward-compatible access to optional draft image verification.
extension UserBlogDraftImageRecovery on UserBlogMediaOperations {
  /// Verifies references, or reports that this adapter lacks the capability.
  Future<DataReadResult<UserBlogDraftImageRestoration, Object?>>
  restoreDraftImages(
    UserBlogEditorPreparation preparation, {
    required List<UserBlogDraftImageReference> images,
    ForumRequestCancellation? cancellation,
  }) {
    final service = this;
    if (service is UserBlogDraftImageRestorer) {
      return (service as UserBlogDraftImageRestorer).restoreDraftImages(
        preparation,
        images: images,
        cancellation: cancellation,
      );
    }
    return Future.value(
      const DataReadFailure(
        kind: DataReadFailureKind.unsupported,
        code: 'blog_draft_images_unsupported',
        diagnosticMessage: 'blog_draft_images_unsupported',
      ),
    );
  }
}
