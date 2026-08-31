/// Source-neutral command contract for submitting a thread poll vote.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// Business capabilities exposed by a poll-vote command source.
enum ThreadPollVoteCapability {
  /// The source validates stable forum and thread identities.
  stableThreadIdentity,

  /// The source preserves the caller's ordered option selection.
  orderedOptionSelection,

  /// The source can submit a vote with explicit server evidence.
  commandSubmission,
}

/// Fail-closed capabilities for poll-vote submission.
final class ThreadPollVoteCapabilities {
  /// Creates capabilities from explicit support values.
  const ThreadPollVoteCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<ThreadPollVoteCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ThreadPollVoteCapability capability) =>
      values.supports(capability);
}

/// One source-neutral poll vote submission.
final class ThreadPollVoteSubmission {
  /// Creates a poll vote for one thread.
  const ThreadPollVoteSubmission({
    required this.fid,
    required this.tid,
    required this.optionIds,
    this.cancellation,
  });

  /// Stable forum identity containing the thread.
  final String fid;

  /// Stable thread identity containing the poll.
  final String tid;

  /// Ordered, unique positive option identities selected by the user.
  final List<String> optionIds;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Confirmed poll-vote receipt that excludes server payloads.
final class ThreadPollVoteReceipt {
  /// Creates a confirmed poll-vote receipt.
  const ThreadPollVoteReceipt({
    required this.fid,
    required this.tid,
    required this.optionIds,
  });

  /// Confirmed forum identity.
  final String fid;

  /// Confirmed thread identity.
  final String tid;

  /// Ordered option identities submitted with the confirmed command.
  final List<String> optionIds;
}

/// Submits a poll vote without exposing a source-specific HTML form.
abstract interface class ThreadPollVoteCommand {
  /// Capabilities proved by this command source.
  ThreadPollVoteCapabilities get capabilities;

  /// Executes the command without exposing source payloads.
  Future<DataCommandResult<ThreadPollVoteReceipt>> execute(
    ThreadPollVoteSubmission submission,
  );
}
