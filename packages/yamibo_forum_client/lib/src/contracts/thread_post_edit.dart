/// Source-neutral contracts for preparing and editing existing forum posts.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// Capabilities proved by a post-edit source.
enum ThreadPostEditCapability {
  /// The source proves forum, thread, post, and page identities.
  stableTargetIdentity,

  /// The source can edit an ordinary thread's first post.
  ordinaryFirstPost,

  /// The source can edit an ordinary reply when the server permits it.
  ordinaryReply,

  /// The source preserves the server's current signature setting.
  signature,

  /// The source preserves and associates image attachment identities.
  imageAttachments,

  /// The source can submit a prepared edit command.
  commandSubmission,

  /// An inconclusive command can be checked with a fresh preparation read.
  readbackConfirmation,
}

/// Fail-closed capabilities for post editing.
final class ThreadPostEditCapabilities {
  /// Creates capabilities from explicit support values.
  const ThreadPostEditCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<ThreadPostEditCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ThreadPostEditCapability capability) =>
      values.supports(capability);
}

/// Kind of existing post being edited.
enum ThreadPostEditTargetKind {
  /// The thread's first post, including its subject.
  firstPost,

  /// A reply post whose subject remains server-managed.
  reply,
}

/// Stable identity and server form reference for one editable post.
final class ThreadPostEditTarget {
  /// Creates an edit target proved by the current thread document.
  const ThreadPostEditTarget({
    required this.formUri,
    required this.fid,
    required this.tid,
    required this.pid,
    required this.page,
    required this.kind,
  });

  /// Same-site edit-form URI supplied by the current thread page.
  final Uri formUri;

  /// Stable forum identity.
  final String fid;

  /// Stable thread identity.
  final String tid;

  /// Stable post identity.
  final String pid;

  /// Page containing the post when the edit entry was discovered.
  final int page;

  /// Whether this target is the first post or a reply.
  final ThreadPostEditTargetKind kind;

  /// Whether this target includes an editable thread subject.
  bool get isFirstPost => kind == ThreadPostEditTargetKind.firstPost;

  @override
  bool operator ==(Object other) =>
      other is ThreadPostEditTarget &&
      other.formUri == formUri &&
      other.fid == fid &&
      other.tid == tid &&
      other.pid == pid &&
      other.page == page &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(formUri, fid, tid, pid, page, kind);
}

/// Requests a fresh server edit form.
final class ThreadPostEditPreparationRequest {
  /// Creates a preparation request for [target].
  const ThreadPostEditPreparationRequest({
    required this.target,
    this.referer,
    this.cancellation,
  });

  /// Expected edit target.
  final ThreadPostEditTarget target;

  /// Optional same-site page reference used as the HTTP Referer.
  final Uri? referer;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// One image attachment currently exposed by the edit form.
final class ThreadPostEditImageAttachment {
  /// Creates a source-neutral existing image projection.
  const ThreadPostEditImageAttachment({
    required this.aid,
    required this.imageUri,
    required this.isAssociated,
    this.description = '',
    this.fileName,
  });

  /// Stable positive attachment identity.
  final String aid;

  /// Validated image URI used for previewing the attachment.
  final Uri imageUri;

  /// Whether the server currently associates this image with the post body.
  final bool isAssociated;

  /// Current server-provided attachment description.
  final String description;

  /// Optional server-provided file name.
  final String? fileName;
}

/// Opaque proof produced by a compatible edit-form adapter.
///
/// It contains dynamic form fields and must be preserved unchanged. Hosts
/// must not inspect, persist, log, or synthesize this token.
abstract interface class ThreadPostEditPreparationToken {}

/// Current editable projection of one ordinary post.
final class ThreadPostEditPreparation {
  /// Creates a validated edit preparation.
  const ThreadPostEditPreparation({
    required this.target,
    required this.sourceUri,
    required this.subject,
    required this.message,
    required this.useSignature,
    required this.existingImages,
    required this.revision,
    required this.token,
  });

  /// Proven edit target.
  final ThreadPostEditTarget target;

  /// Final same-site URI of the preparation response.
  final Uri sourceUri;

  /// Current subject. Replies normally expose an empty subject.
  final String subject;

  /// Current BBCode message.
  final String message;

  /// Current server signature choice.
  final bool useSignature;

  /// Ordered image attachments exposed by the form.
  final List<ThreadPostEditImageAttachment> existingImages;

  /// Opaque, non-secret revision fingerprint for conflict detection.
  final String revision;

  /// Dynamic server proof required for submission.
  final ThreadPostEditPreparationToken token;
}

/// User-authored changes submitted through a prepared edit form.
final class ThreadPostEditSubmission {
  /// Creates an edit submission.
  const ThreadPostEditSubmission({
    required this.preparation,
    required this.subject,
    required this.message,
    required this.useSignature,
    this.newImageAttachmentIds = const <String>[],
    this.removedImageAttachmentIds = const <String>[],
    this.cancellation,
  });

  /// Fresh preparation and opaque server proof.
  final ThreadPostEditPreparation preparation;

  /// Updated subject; ignored only when the prepared target is a reply.
  final String subject;

  /// Updated BBCode message.
  final String message;

  /// Whether the edited post should show the user's signature.
  final bool useSignature;

  /// Ordered newly uploaded image attachment identities referenced by message.
  final List<String> newImageAttachmentIds;

  /// Existing image identities explicitly removed before submission.
  final List<String> removedImageAttachmentIds;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Server publication state after a confirmed edit.
enum ThreadPostEditPublicationState {
  /// The edited post is immediately visible.
  published,

  /// The edited post is awaiting moderation.
  pendingModeration,
}

/// Evidence that proved an edit was applied.
enum ThreadPostEditConfirmation {
  /// Discuz returned the matching AJAX success callback.
  serverCallback,

  /// A fresh edit form proved the submitted state after an ambiguous response.
  readback,
}

/// Confirmed edit receipt without transport payloads.
final class ThreadPostEditReceipt {
  /// Creates a confirmed edit receipt.
  const ThreadPostEditReceipt({
    required this.target,
    required this.publicationState,
    required this.confirmation,
  });

  /// Edited target.
  final ThreadPostEditTarget target;

  /// Publication or moderation state proved by the response.
  final ThreadPostEditPublicationState publicationState;

  /// Evidence used to confirm the command.
  final ThreadPostEditConfirmation confirmation;
}

/// Loads and validates the current server form for editing a post.
abstract interface class ThreadPostEditPreparationRepository {
  /// Capabilities proved by this source.
  ThreadPostEditCapabilities get capabilities;

  /// Loads a fresh preparation without exposing dynamic server fields.
  Future<DataReadResult<ThreadPostEditPreparation, ThreadPostEditCapabilities>>
  load(ThreadPostEditPreparationRequest request);
}

/// Submits an edit through a previously prepared ordinary-post form.
abstract interface class ThreadPostEditCommand {
  /// Capabilities proved by this source.
  ThreadPostEditCapabilities get capabilities;

  /// Executes [submission] without retrying ordinary transport failures.
  Future<DataCommandResult<ThreadPostEditReceipt>> execute(
    ThreadPostEditSubmission submission,
  );
}
