/// Source-neutral preparation and command contracts for creating threads and
/// replying to threads or individual posts.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// Capabilities exposed by a thread-creation source.
enum ThreadCreationCapability {
  /// The source proves the target forum identity.
  stableForumIdentity,

  /// The source provides the forum's ordered thread-type choices.
  threadTypes,

  /// The source provides the forum's ordered structured-category choices.
  threadSorts,

  /// The source provides subject and message length limits when available.
  contentLimits,

  /// The source accepts ordinary thread submissions.
  ordinaryThread,

  /// The source accepts poll thread submissions.
  pollThread,

  /// The source accepts attachment identities prepared by the Host.
  attachments,

  /// The source accepts thread tags.
  tags,

  /// The source accepts a minimum read-access value.
  minimumReadAccess,

  /// The source can submit a prepared thread-creation command.
  commandSubmission,
}

/// Fail-closed capabilities for thread preparation and creation.
final class ThreadCreationCapabilities {
  /// Creates capabilities from explicit support values.
  const ThreadCreationCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<ThreadCreationCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ThreadCreationCapability capability) =>
      values.supports(capability);
}

/// Opaque proof produced by a compatible thread-preparation adapter.
///
/// Applications must preserve this token unchanged and must not inspect it.
abstract interface class ThreadCreationPreparationToken {}

/// Requests the current server preparation for creating a thread.
final class ThreadCreationPreparationRequest {
  /// Creates a preparation request for [fid].
  const ThreadCreationPreparationRequest({
    required this.fid,
    this.cancellation,
  });

  /// Stable forum identity.
  final String fid;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// One server-provided thread-type choice.
final class ThreadCreationType {
  /// Creates a thread-type choice.
  const ThreadCreationType({required this.id, required this.name});

  /// Stable Discuz type identity.
  final String id;

  /// Server-provided display name.
  final String name;
}

/// One server-provided structured-category choice.
final class ThreadCreationSort {
  /// Creates a structured-category choice.
  const ThreadCreationSort({required this.id, required this.name});

  /// Stable Discuz sort identity.
  final String id;

  /// Server-provided display name.
  final String name;
}

/// Current server preparation for creating a thread in one forum.
final class ThreadCreationPreparation {
  /// Creates a prepared thread-creation form projection.
  const ThreadCreationPreparation({
    required this.fid,
    required this.forumName,
    required this.threadTypes,
    required this.threadSorts,
    required this.typeRequired,
    required this.sortRequired,
    required this.maxSubjectLength,
    required this.maxMessageLength,
    required this.token,
  });

  /// Proven forum identity.
  final String fid;

  /// Server-provided forum name.
  final String forumName;

  /// Ordered thread-type choices.
  final List<ThreadCreationType> threadTypes;

  /// Ordered structured-category choices.
  final List<ThreadCreationSort> threadSorts;

  /// Whether a non-zero thread type is required.
  final bool typeRequired;

  /// Whether a structured category is required.
  ///
  /// A client that does not support structured-category fields must fail
  /// closed when this value is true.
  final bool sortRequired;

  /// Maximum subject length, or zero when the source declares no limit.
  final int maxSubjectLength;

  /// Maximum message length, or zero when the source declares no limit.
  final int maxMessageLength;

  /// Opaque adapter proof required for safe submission.
  final ThreadCreationPreparationToken token;

  /// Whether the preparation declares a subject limit.
  bool get hasSubjectLimit => maxSubjectLength > 0;

  /// Whether the preparation declares a message limit.
  bool get hasMessageLimit => maxMessageLength > 0;
}

/// Thread kind supported by the source-neutral creation command.
enum ThreadCreationKind {
  /// An ordinary discussion thread.
  ordinary,

  /// A poll thread.
  poll,
}

/// Poll fields submitted with a poll thread.
final class ThreadPollSubmission {
  /// Creates a poll submission.
  const ThreadPollSubmission({
    required this.options,
    required this.maximumChoices,
    required this.expirationDays,
    required this.publicVoters,
    required this.resultsAfterVote,
  });

  /// Ordered non-empty poll options.
  final List<String> options;

  /// Maximum number of choices accepted from one voter.
  final int maximumChoices;

  /// Number of days until expiry, or zero for no expiry.
  final int expirationDays;

  /// Whether voter identities are public.
  final bool publicVoters;

  /// Whether results are hidden until the current user votes.
  final bool resultsAfterVote;
}

/// User-authored data submitted against one prepared creation form.
final class ThreadCreationSubmission {
  /// Creates a thread-creation submission.
  const ThreadCreationSubmission({
    required this.preparation,
    required this.subject,
    required this.message,
    required this.typeId,
    required this.useSignature,
    required this.notifyAuthor,
    required this.disableBbCode,
    required this.disableSmileys,
    required this.disableUrlParsing,
    this.attachmentIds = const <String>[],
    this.tags = const <String>[],
    this.kind = ThreadCreationKind.ordinary,
    this.poll,
    this.minimumReadAccess = 0,
    this.cancellation,
  });

  /// Current server preparation and opaque proof.
  final ThreadCreationPreparation preparation;

  /// User-entered subject.
  final String subject;

  /// User-entered BBCode message.
  final String message;

  /// Selected thread-type identity, or `0` for no type.
  final String typeId;

  /// Whether the user's signature should be shown.
  final bool useSignature;

  /// Whether Discuz should notify the author where applicable.
  final bool notifyAuthor;

  /// Whether BBCode parsing is disabled.
  final bool disableBbCode;

  /// Whether smiley parsing is disabled.
  final bool disableSmileys;

  /// Whether automatic URL parsing is disabled.
  final bool disableUrlParsing;

  /// Ordered attachment identities referenced by [message].
  final List<String> attachmentIds;

  /// Ordered normalized thread tags.
  final List<String> tags;

  /// Ordinary or poll thread kind.
  final ThreadCreationKind kind;

  /// Poll fields when [kind] is [ThreadCreationKind.poll].
  final ThreadPollSubmission? poll;

  /// Minimum read access in the inclusive Discuz range `0..255`.
  final int minimumReadAccess;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Server publication state proved by a successful command response.
enum ThreadPublicationState {
  /// The created content is immediately published.
  published,

  /// The created content is awaiting moderation.
  pendingModeration,
}

/// Strength of evidence for a requested minimum read-access value.
enum ThreadReadAccessEvidenceKind {
  /// The submission requested unrestricted access (`0`).
  unrestricted,

  /// A read-back confirmed the requested non-zero value.
  confirmed,

  /// A read-back proved that the server stored another value.
  serverAdjusted,

  /// Creation was proved, but the optional read-back was inconclusive.
  unverified,
}

/// Evidence attached to a confirmed thread-creation receipt.
final class ThreadReadAccessEvidence {
  /// Creates read-access evidence.
  const ThreadReadAccessEvidence({
    required this.kind,
    required this.requested,
    this.actual,
  });

  /// Evidence strength and outcome.
  final ThreadReadAccessEvidenceKind kind;

  /// Value submitted by the caller.
  final int requested;

  /// Value proved by read-back, when available.
  final int? actual;
}

/// Confirmed thread-creation receipt without server payloads.
final class ThreadCreationReceipt {
  /// Creates a confirmed receipt.
  const ThreadCreationReceipt({
    required this.tid,
    required this.pid,
    required this.publicationState,
    required this.readAccess,
  });

  /// Created thread identity.
  final String tid;

  /// Created first-post identity.
  final String pid;

  /// Publication or moderation state.
  final ThreadPublicationState publicationState;

  /// Evidence for the submitted minimum read-access value.
  final ThreadReadAccessEvidence readAccess;
}

/// Reads and validates the current thread-creation preparation.
abstract interface class ThreadCreationPreparationRepository {
  /// Capabilities proved by this source.
  ThreadCreationCapabilities get capabilities;

  /// Loads the preparation without exposing formhash or transport fields.
  Future<DataReadResult<ThreadCreationPreparation, ThreadCreationCapabilities>>
  load(ThreadCreationPreparationRequest request);
}

/// Creates a thread through a previously prepared server form.
abstract interface class ThreadCreationCommand {
  /// Capabilities proved by this source.
  ThreadCreationCapabilities get capabilities;

  /// Executes [submission] without retrying ordinary transport failures.
  Future<DataCommandResult<ThreadCreationReceipt>> execute(
    ThreadCreationSubmission submission,
  );
}

/// Capabilities exposed by a thread-reply source.
enum ThreadReplyCapability {
  /// The source proves forum, thread, and optional post identities.
  stableTargetIdentity,

  /// The source can prepare a reply to one specific post.
  postReplyPreparation,

  /// The source can submit an ordinary thread reply.
  threadReply,

  /// The source can submit a prepared reply to one post.
  postReply,

  /// The source accepts attachment identities prepared by the Host.
  attachments,

  /// The source can submit a reply command.
  commandSubmission,
}

/// Fail-closed capabilities for reply preparation and submission.
final class ThreadReplyCapabilities {
  /// Creates capabilities from explicit support values.
  const ThreadReplyCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<ThreadReplyCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ThreadReplyCapability capability) =>
      values.supports(capability);
}

/// Kind of reply target.
enum ThreadReplyTargetKind {
  /// Reply to the thread as a whole.
  thread,

  /// Reply to one specific post.
  post,
}

/// Stable identity of a thread or post reply target.
final class ThreadReplyTarget {
  /// Creates an ordinary thread reply target.
  const ThreadReplyTarget.thread({required this.fid, required this.tid})
    : kind = ThreadReplyTargetKind.thread,
      pid = null;

  /// Creates a reply target for one post.
  const ThreadReplyTarget.post({
    required this.fid,
    required this.tid,
    required this.pid,
  }) : kind = ThreadReplyTargetKind.post;

  /// Target kind.
  final ThreadReplyTargetKind kind;

  /// Stable forum identity.
  final String fid;

  /// Stable thread identity.
  final String tid;

  /// Stable post identity for post replies.
  final String? pid;
}

/// Opaque proof produced by a compatible post-reply preparation adapter.
///
/// Applications must preserve this token unchanged and must not inspect it.
abstract interface class ThreadReplyPreparationToken {}

/// Requests the current server form for replying to one post.
final class ThreadReplyPreparationRequest {
  /// Creates a post-reply preparation request.
  const ThreadReplyPreparationRequest({
    required this.target,
    required this.formUri,
    this.referer,
    this.cancellation,
  });

  /// Expected post target.
  final ThreadReplyTarget target;

  /// Same-site reply-form URI supplied by the current thread page.
  final Uri formUri;

  /// Optional same-site page reference used as the HTTP Referer.
  final Uri? referer;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Prepared post-reply form projection.
final class ThreadReplyPreparation {
  /// Creates a prepared reply projection.
  const ThreadReplyPreparation({
    required this.target,
    required this.token,
    this.quotePreview,
  });

  /// Proven post target.
  final ThreadReplyTarget target;

  /// Human-readable quote preview supplied by the server form.
  final String? quotePreview;

  /// Opaque adapter proof required for safe submission.
  final ThreadReplyPreparationToken token;
}

/// User-authored data submitted as a thread or post reply.
final class ThreadReplySubmission {
  /// Creates a reply submission.
  const ThreadReplySubmission({
    required this.target,
    required this.message,
    required this.useSignature,
    this.preparation,
    this.attachmentIds = const <String>[],
    this.cancellation,
  });

  /// Stable reply target.
  final ThreadReplyTarget target;

  /// Prepared server form for post replies.
  final ThreadReplyPreparation? preparation;

  /// User-entered BBCode message.
  final String message;

  /// Whether the user's signature should be shown.
  final bool useSignature;

  /// Ordered attachment identities referenced by [message].
  final List<String> attachmentIds;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Confirmed reply receipt without server response payloads.
final class ThreadReplyReceipt {
  /// Creates a confirmed reply receipt.
  const ThreadReplyReceipt({
    required this.tid,
    required this.pid,
    required this.publicationState,
  });

  /// Replied thread identity.
  final String tid;

  /// Created reply-post identity.
  final String pid;

  /// Publication or moderation state.
  final ThreadPublicationState publicationState;
}

/// Reads and validates a server form for replying to one post.
abstract interface class ThreadReplyPreparationRepository {
  /// Capabilities proved by this source.
  ThreadReplyCapabilities get capabilities;

  /// Loads a post-reply form and preserves its hidden fields in an opaque token.
  Future<DataReadResult<ThreadReplyPreparation, ThreadReplyCapabilities>> load(
    ThreadReplyPreparationRequest request,
  );
}

/// Submits ordinary thread replies and prepared post replies.
abstract interface class ThreadReplyCommand {
  /// Capabilities proved by this source.
  ThreadReplyCapabilities get capabilities;

  /// Executes [submission] without retrying ordinary transport failures.
  Future<DataCommandResult<ThreadReplyReceipt>> execute(
    ThreadReplySubmission submission,
  );
}
