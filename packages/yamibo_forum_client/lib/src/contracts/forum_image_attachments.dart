/// Source-neutral contracts for forum image attachment management.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';
import 'forum_resource.dart';

/// Capabilities exposed by image attachment upload sources.
enum ForumImageAttachmentUploadCapability {
  preparation,
  streamedUpload,
  progress,
  cancellation,
  preciseServerRejection,
}

/// Explicit upload capability declaration.
final class ForumImageAttachmentUploadCapabilities {
  /// Creates upload capabilities.
  const ForumImageAttachmentUploadCapabilities({required this.values});

  /// Support values for each capability.
  final DataCapabilitySet<ForumImageAttachmentUploadCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ForumImageAttachmentUploadCapability capability) =>
      values.supports(capability);
}

/// Opaque server proof required by the upload command.
abstract interface class ForumImageAttachmentUploadPreparationToken {}

/// Per-extension upload rule proved by the preparation response.
final class ForumImageAttachmentExtensionRule {
  /// Creates one normalized extension rule.
  const ForumImageAttachmentExtensionRule({
    required this.extension,
    this.maximumBytes,
  });

  /// Lower-case extension without a leading dot.
  final String extension;

  /// Per-file maximum, or `null` when the server declares no explicit limit.
  final int? maximumBytes;
}

/// Request for current upload permission in one forum.
final class ForumImageAttachmentUploadPreparationRequest {
  /// Creates an upload preparation request.
  const ForumImageAttachmentUploadPreparationRequest({
    required this.fid,
    this.cancellation,
  });

  /// Stable forum identity.
  final String fid;

  /// Optional cooperative cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Current server-side permission and limits for image uploads.
final class ForumImageAttachmentUploadPreparation {
  /// Creates a validated preparation.
  const ForumImageAttachmentUploadPreparation({
    required this.fid,
    required this.extensionRules,
    required this.token,
    this.remainingBytes,
    this.remainingCount,
  });

  /// Confirmed forum identity.
  final String fid;

  /// Allowed image extensions in server order.
  final List<ForumImageAttachmentExtensionRule> extensionRules;

  /// Remaining total bytes, or `null` when unlimited.
  final int? remainingBytes;

  /// Remaining attachment count, or `null` when unlimited.
  final int? remainingCount;

  /// Opaque proof consumed by the matching command adapter.
  final ForumImageAttachmentUploadPreparationToken token;
}

/// A local image supplied to the package as a replay-safe stream.
final class ForumImageAttachmentContent {
  /// Creates image content for one upload.
  const ForumImageAttachmentContent({
    required this.fileName,
    required this.mimeType,
    required this.contentLength,
    required this.openRead,
  });

  /// File name visible to Discuz.
  final String fileName;

  /// Declared image MIME type.
  final String mimeType;

  /// Exact file length.
  final int contentLength;

  /// Opens a fresh byte stream for every transport attempt.
  final Stream<List<int>> Function() openRead;
}

/// Submission of one image using a validated preparation.
final class ForumImageAttachmentUploadSubmission {
  /// Creates an image upload submission.
  const ForumImageAttachmentUploadSubmission({
    required this.preparation,
    required this.content,
    this.cancellation,
    this.onProgress,
  });

  /// Current server preparation.
  final ForumImageAttachmentUploadPreparation preparation;

  /// Replay-safe local image content.
  final ForumImageAttachmentContent content;

  /// Optional cooperative cancellation.
  final ForumRequestCancellation? cancellation;

  /// Optional normalized progress callback.
  final void Function(double progress)? onProgress;
}

/// Confirmed remote attachment identity.
final class ForumImageAttachmentUploadReceipt {
  /// Creates an upload receipt.
  const ForumImageAttachmentUploadReceipt({required this.aid});

  /// Positive Discuz attachment identity.
  final String aid;
}

/// Loads current image upload permission.
abstract interface class ForumImageAttachmentUploadPreparationRepository {
  /// Capabilities proved by this source.
  ForumImageAttachmentUploadCapabilities get capabilities;

  /// Loads current server permission and an opaque upload token.
  Future<
    DataReadResult<
      ForumImageAttachmentUploadPreparation,
      ForumImageAttachmentUploadCapabilities
    >
  >
  load(ForumImageAttachmentUploadPreparationRequest request);
}

/// Uploads one prepared image attachment.
abstract interface class ForumImageAttachmentUploadCommand {
  /// Capabilities proved by this source.
  ForumImageAttachmentUploadCapabilities get capabilities;

  /// Executes one image upload.
  Future<DataCommandResult<ForumImageAttachmentUploadReceipt>> execute(
    ForumImageAttachmentUploadSubmission submission,
  );
}

/// Capabilities of the unused image attachment directory.
enum ForumUnusedImageAttachmentCapability {
  stableAttachmentIdentity,
  orderedAttachments,
  thumbnailReference,
  deletionProof,
}

/// Effective directory capabilities.
final class ForumUnusedImageAttachmentCapabilities {
  /// Creates directory capabilities.
  const ForumUnusedImageAttachmentCapabilities({required this.values});

  /// Support values for each capability.
  final DataCapabilitySet<ForumUnusedImageAttachmentCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ForumUnusedImageAttachmentCapability capability) =>
      values.supports(capability);
}

/// Opaque proof that an attachment belonged to a loaded unused directory.
abstract interface class ForumUnusedImageAttachmentDirectoryToken {}

/// One unused image attachment.
final class ForumUnusedImageAttachment {
  /// Creates an unused image entry.
  const ForumUnusedImageAttachment({
    required this.aid,
    required this.thumbnail,
    this.fileName = '',
    this.description = '',
  });

  /// Positive attachment identity.
  final String aid;

  /// Validated thumbnail resource reference.
  final ForumResourceReference thumbnail;

  /// Server-provided file name.
  final String fileName;

  /// Server-provided attachment description.
  final String description;
}

/// Authenticated user's ordered unused image directory.
final class ForumUnusedImageAttachmentDirectory {
  /// Creates a validated directory.
  const ForumUnusedImageAttachmentDirectory({
    required this.items,
    required this.token,
  });

  /// Ordered unused attachments.
  final List<ForumUnusedImageAttachment> items;

  /// Opaque directory proof used by deletion commands.
  final ForumUnusedImageAttachmentDirectoryToken token;
}

/// Request for the current unused image directory.
final class ForumUnusedImageAttachmentDirectoryRequest {
  /// Creates a directory request.
  const ForumUnusedImageAttachmentDirectoryRequest({this.cancellation});

  /// Optional cooperative cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Reads unused image attachments for the current authenticated user.
abstract interface class ForumUnusedImageAttachmentDirectoryRepository {
  /// Effective source capabilities.
  ForumUnusedImageAttachmentCapabilities get capabilities;

  /// Loads the current uncached directory.
  Future<
    DataReadResult<
      ForumUnusedImageAttachmentDirectory,
      ForumUnusedImageAttachmentCapabilities
    >
  >
  load(ForumUnusedImageAttachmentDirectoryRequest request);
}

/// Receipt proving one attachment is absent after deletion.
final class ForumImageAttachmentDeleteReceipt {
  /// Creates a delete receipt.
  const ForumImageAttachmentDeleteReceipt({
    required this.aid,
    required this.deletedCount,
  });

  /// Deleted or confirmed-absent attachment identity.
  final String aid;

  /// Server deletion count, or zero when absence was proved by read-back.
  final int deletedCount;
}

/// Deletes one attachment from a previously loaded unused directory.
final class DeleteUnusedImageAttachmentRequest {
  /// Creates an unused attachment delete request.
  const DeleteUnusedImageAttachmentRequest({
    required this.aid,
    required this.directoryToken,
    this.cancellation,
  });

  /// Attachment identity.
  final String aid;

  /// Proof from the directory containing [aid].
  final ForumUnusedImageAttachmentDirectoryToken directoryToken;

  /// Optional cooperative cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Deletes one existing image attachment from a post edit session.
final class DeletePostImageAttachmentRequest {
  /// Creates a post attachment delete request.
  const DeletePostImageAttachmentRequest({
    required this.tid,
    required this.pid,
    required this.aid,
    this.cancellation,
  });

  /// Stable thread identity.
  final String tid;

  /// Stable post identity.
  final String pid;

  /// Stable attachment identity.
  final String aid;

  /// Optional cooperative cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Command for deleting an unused image attachment.
abstract interface class ForumUnusedImageAttachmentDeleteCommand {
  /// Deletes [request] and confirms absence through a directory read-back when
  /// the direct response is inconclusive.
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeleteUnusedImageAttachmentRequest request,
  );
}

/// Command for deleting an image attachment bound to an existing post.
abstract interface class ForumPostImageAttachmentDeleteCommand {
  /// Executes the delete request. The Host may perform a richer edit-form
  /// read-back when the result is inconclusive.
  Future<DataCommandResult<ForumImageAttachmentDeleteReceipt>> execute(
    DeletePostImageAttachmentRequest request,
  );
}
