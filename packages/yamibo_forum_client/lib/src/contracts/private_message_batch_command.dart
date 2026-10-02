import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// Capabilities proved by a fresh desktop private-message form.
enum ForumPrivateMessageBatchCapability {
  /// One request starts separate direct conversations, not a group chat.
  separateConversations,

  /// The source can submit a freshly prepared form.
  commandSubmission,
}

/// Fail-closed capabilities for batch preparation.
final class ForumPrivateMessageBatchCapabilities {
  /// Creates a capability set.
  const ForumPrivateMessageBatchCapabilities({required this.values});

  /// Explicit source support values.
  final DataCapabilitySet<ForumPrivateMessageBatchCapability> values;
}

/// Opaque proof of one preparation; applications must not inspect or persist it.
///
/// The command always prepares again and accepts no caller-supplied token.
abstract interface class ForumPrivateMessageBatchPreparationToken {}

/// Requests the current desktop compose form without sending a message.
final class ForumPrivateMessageBatchPreparationRequest {
  /// Creates a cancellable preparation request.
  const ForumPrivateMessageBatchPreparationRequest({this.cancellation});

  /// Cancels an obsolete account or composer preparation.
  final ForumRequestCancellation? cancellation;
}

/// Validated compose capability, excluding raw form fields and session secrets.
final class ForumPrivateMessageBatchPreparation {
  /// Creates a prepared form projection.
  const ForumPrivateMessageBatchPreparation({required this.token});

  /// Opaque adapter-owned proof; not reusable as a command submission token.
  final ForumPrivateMessageBatchPreparationToken token;
}

/// Inspects whether the current session can prepare a desktop batch.
abstract interface class ForumPrivateMessageBatchPreparationRepository {
  /// Loads a fresh form; results and tokens are never persisted.
  Future<
    DataReadResult<
      ForumPrivateMessageBatchPreparation,
      ForumPrivateMessageBatchCapabilities
    >
  >
  prepare(ForumPrivateMessageBatchPreparationRequest request);
}

/// Sends the same content as separate direct messages in one server request.
final class ForumPrivateMessageBatchSubmission {
  /// Creates a submission; each username denotes one separate conversation.
  ForumPrivateMessageBatchSubmission({
    required List<String> usernames,
    required this.message,
    this.cancellation,
  }) : usernames = List.unmodifiable(usernames);

  /// Recipient usernames, not comma-delimited text or group IDs.
  final List<String> usernames;

  /// Message content, including supported forum smiley codes or BBCode.
  final String message;

  /// Cancellation before dispatch prevents the write; after dispatch it may
  /// leave the outcome unknown and must never trigger automatic resubmission.
  final ForumRequestCancellation? cancellation;
}

/// Confirms a batch caused at least one write, not delivery to every recipient.
///
/// Discuz reports its pre-UCenter accepted count. UCenter may silently omit
/// recipients who block the sender, so this receipt deliberately provides no
/// per-recipient success state or fabricated message ID.
final class ForumPrivateMessageBatchReceipt {
  /// Creates a receipt from a validated aggregate response.
  ForumPrivateMessageBatchReceipt({
    required List<String> usernames,
    required this.serverReportedAcceptedCount,
    required List<String> excludedUsernames,
  }) : usernames = List.unmodifiable(usernames),
       excludedUsernames = List.unmodifiable(excludedUsernames);

  /// Trimmed, exact-case, deduplicated submitted usernames.
  final List<String> usernames;

  /// Discuz's accepted count, which may overstate actual UCenter recipients.
  final int serverReportedAcceptedCount;

  /// Submitted usernames explicitly excluded before the UCenter write.
  final List<String> excludedUsernames;

  /// Whether this receipt confirms the only submitted recipient's write.
  ///
  /// Multiple submitted recipients never acquire individual success claims.
  bool get confirmsSingleRecipient =>
      usernames.length == 1 &&
      serverReportedAcceptedCount == 1 &&
      excludedUsernames.isEmpty;
}

/// Freshly prepares and submits one desktop batch; never retries a write.
abstract interface class ForumPrivateMessageBatchCommand {
  /// Obtains a fresh desktop form and submits at most one POST.
  ///
  /// Only [DataCommandApplied] permits local updates. Its aggregate receipt
  /// must not be represented as proof that every requested user received it.
  Future<DataCommandResult<ForumPrivateMessageBatchReceipt>> execute(
    ForumPrivateMessageBatchSubmission submission,
  );
}
