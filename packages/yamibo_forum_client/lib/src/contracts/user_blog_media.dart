/// Transient journal images and the editor's dedicated smiley catalog.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
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
