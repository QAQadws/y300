/// Source-neutral contracts for reading and changing daily sign-in state.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// A sign-in state confirmed for one authenticated user and forum day.
enum ForumDailySignInStatus {
  /// The forum confirmed today's sign-in.
  signed,

  /// The current page reports no record; eligibility and cache freshness are
  /// not implied.
  unsigned,
}

/// One display statistic in the order supplied by the forum.
final class ForumDailySignInStatistic {
  /// Creates a display statistic without interpreting its source wording.
  const ForumDailySignInStatistic({required this.label, required this.value});

  /// Source-provided statistic label.
  final String label;

  /// Source-provided statistic value.
  final String value;
}

/// A page-reported state for a verified user and forum-defined calendar day.
final class ForumDailySignInSnapshot {
  /// Creates a confirmed sign-in snapshot.
  const ForumDailySignInSnapshot({
    required this.userId,
    required this.forumDay,
    required this.status,
    this.statistics,
  });

  /// Stable, verified forum user ID; never an unverified requested ID alone.
  final String userId;

  /// Server-rendered forum day in `YYYYMMDD` form.
  final String forumDay;

  /// Today's sign-in state. Ambiguous pages must produce a read failure.
  final ForumDailySignInStatus status;

  /// Optional statistics in source order, or `null` when not established.
  final List<ForumDailySignInStatistic>? statistics;
}

/// Request for a fresh sign-in state of one authenticated user.
final class ForumDailySignInQuery {
  /// Creates a sign-in state query.
  const ForumDailySignInQuery({required this.userId, this.cancellation});

  /// Expected forum user ID, checked against the response identity.
  final String userId;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Capabilities of a daily sign-in read source.
enum ForumDailySignInReadCapability {
  /// Classify the current page's signed or unsigned day marker.
  todayStatus,

  /// Provide ordered, source-reported statistics.
  orderedStatistics,
}

/// Capabilities declared by a daily sign-in read source.
final class ForumDailySignInSourceCapabilities {
  /// Creates a source capability declaration.
  const ForumDailySignInSourceCapabilities({required this.values});

  /// Support values for each read capability.
  final DataCapabilitySet<ForumDailySignInReadCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ForumDailySignInReadCapability capability) =>
      values.supports(capability);

  /// Converts source capabilities to capabilities for one read.
  ForumDailySignInReadCapabilities toReadCapabilities() =>
      ForumDailySignInReadCapabilities(values: values);
}

/// Capabilities effective for one daily sign-in read.
final class ForumDailySignInReadCapabilities {
  /// Creates an effective read capability declaration.
  const ForumDailySignInReadCapabilities({required this.values});

  /// Support values for each read capability.
  final DataCapabilitySet<ForumDailySignInReadCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ForumDailySignInReadCapability capability) =>
      values.supports(capability);

  /// Returns the conservative intersection with another read.
  ForumDailySignInReadCapabilities intersect(
    ForumDailySignInReadCapabilities other,
  ) => ForumDailySignInReadCapabilities(values: values.intersect(other.values));
}

/// Reads current daily sign-in page state without a document-cache fallback.
abstract interface class ForumDailySignInRepository {
  /// Capabilities declared by this source.
  ForumDailySignInSourceCapabilities get capabilities;

  /// Loads a fresh response; uncertain identity or state is a read failure.
  Future<
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>
  >
  load(ForumDailySignInQuery query);
}

/// Request to sign in the authenticated user for the current forum day.
final class ForumDailySignInRequest {
  /// Creates a daily sign-in request.
  const ForumDailySignInRequest({
    required this.userId,
    this.expectedForumDay,
    this.cancellation,
  });

  /// Expected forum user ID, checked against the current session.
  final String userId;

  /// Optional day shown to the caller before confirmation, in `YYYYMMDD`.
  /// A changed day prevents submission even if a fresh page is unsigned.
  final String? expectedForumDay;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Proof returned only after the server effect and state are confirmed.
final class ForumDailySignInReceipt {
  /// Creates a confirmed daily sign-in receipt.
  const ForumDailySignInReceipt({required this.userId, required this.forumDay});

  /// Verified forum user ID.
  final String userId;

  /// Confirmed forum day in `YYYYMMDD` form.
  final String forumDay;
}

/// Capabilities of a daily sign-in command source.
enum ForumDailySignInCommandCapability {
  /// Submit a normal sign-in for the current forum day.
  signIn,

  /// Prove a positive final state through a separate fresh read.
  readBackConfirmation,
}

/// Fail-closed capability declaration for daily sign-in commands.
final class ForumDailySignInCommandCapabilities {
  /// Creates a command capability declaration.
  const ForumDailySignInCommandCapabilities({required this.values});

  /// Support values for each command capability.
  final DataCapabilitySet<ForumDailySignInCommandCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ForumDailySignInCommandCapability capability) =>
      values.supports(capability);
}

/// Signs in one authenticated user through the configured forum boundary.
abstract interface class ForumDailySignInCommand {
  /// Capabilities declared by this source.
  ForumDailySignInCommandCapabilities get capabilities;

  /// Executes at most one submitted sign-in attempt for this call.
  ///
  /// A result is [DataCommandApplied] only when the effect is proved. Once a
  /// request may have reached the server, an inconclusive result must be
  /// [DataCommandOutcomeUnknown] and must not be automatically retried.
  Future<DataCommandResult<ForumDailySignInReceipt>> execute(
    ForumDailySignInRequest request,
  );
}
