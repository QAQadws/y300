/// Source-neutral preparation and command contracts for rating and commenting.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';

/// Business capabilities exposed while preparing or submitting a post rating.
enum ThreadPostRatingCapability {
  /// The source proves the target thread and post identities.
  stablePostIdentity,

  /// The source provides every score dimension exposed by the server form.
  scoreDimensions,

  /// The source provides server-defined rating-reason suggestions.
  reasonSuggestions,

  /// The source supports the server's author-notification option.
  authorNotification,

  /// The source can submit a rating through an explicit command response.
  commandSubmission,
}

/// Fail-closed source capabilities for rating preparation and submission.
final class ThreadPostRatingCapabilities {
  /// Creates capabilities from explicit support values.
  const ThreadPostRatingCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<ThreadPostRatingCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ThreadPostRatingCapability capability) =>
      values.supports(capability);
}

/// Opaque proof that a rating form was prepared by a compatible adapter.
///
/// Applications must preserve this value unchanged and must not inspect it.
abstract interface class ThreadPostRatingPreparationToken {}

/// Requests the current rating form for one stable post.
final class ThreadPostRatingPreparationRequest {
  /// Creates a rating-form request.
  const ThreadPostRatingPreparationRequest({
    required this.tid,
    required this.pid,
    this.referer,
    this.cancellation,
  });

  /// Stable thread identity.
  final String tid;

  /// Stable post identity.
  final String pid;

  /// Optional same-site page reference used as the HTTP Referer.
  final Uri? referer;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// One independent score dimension exposed by the Discuz rating form.
final class ThreadPostRatingDimension {
  /// Creates a rating dimension.
  const ThreadPostRatingDimension({
    required this.id,
    required this.label,
    required this.minimum,
    required this.maximum,
    required this.initialScore,
    required this.todayRemaining,
  }) : assert(minimum <= maximum),
       assert(initialScore >= minimum && initialScore <= maximum);

  /// Stable form field identity, such as `score1`.
  final String id;

  /// Server-provided display label for the score type.
  final String label;

  /// Inclusive minimum accepted score.
  final int minimum;

  /// Inclusive maximum accepted score.
  final int maximum;

  /// Initial value carried by the prepared server form.
  ///
  /// A client that only exposes a subset of score controls must preserve this
  /// value for every unexposed dimension when submitting the form.
  final int initialScore;

  /// Server-provided remaining score budget for the current day.
  final int todayRemaining;

  /// Default value suitable for an unchanged rating control.
  int get defaultScore => maximum > 0 ? maximum : minimum;
}

/// Whether the prepared form exposes author notification.
enum ThreadPostRatingNotificationPolicy {
  /// The user may choose whether to notify the post author.
  optional,

  /// The server requires author notification.
  required,

  /// The form does not expose author notification.
  unavailable,
}

/// Source-neutral rating form prepared from the current server response.
final class ThreadPostRatingPreparation {
  /// Creates a prepared rating form.
  const ThreadPostRatingPreparation({
    required this.tid,
    required this.pid,
    required this.dimensions,
    required this.reasonSuggestions,
    required this.notificationPolicy,
    required this.notifyAuthorByDefault,
    required this.token,
  });

  /// Proven thread identity.
  final String tid;

  /// Proven post identity.
  final String pid;

  /// Ordered score dimensions from the server form.
  final List<ThreadPostRatingDimension> dimensions;

  /// Ordered server-provided reason suggestions.
  final List<String> reasonSuggestions;

  /// Server policy for notifying the author.
  final ThreadPostRatingNotificationPolicy notificationPolicy;

  /// Initial notification value represented by the server form.
  final bool notifyAuthorByDefault;

  /// Opaque adapter proof required for safe submission.
  final ThreadPostRatingPreparationToken token;
}

/// User-selected rating values submitted against one prepared form.
final class ThreadPostRatingSubmission {
  /// Creates a rating submission.
  const ThreadPostRatingSubmission({
    required this.preparation,
    required this.scores,
    required this.reason,
    required this.notifyAuthor,
    this.cancellation,
  });

  /// Prepared server form and opaque proof.
  final ThreadPostRatingPreparation preparation;

  /// Score value keyed by every prepared dimension identity.
  final Map<String, int> scores;

  /// User-entered rating reason.
  final String reason;

  /// Whether the author should be notified when the form permits a choice.
  final bool notifyAuthor;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Confirmed rating-command receipt that excludes server response payloads.
final class ThreadPostRatingReceipt {
  /// Creates a confirmed receipt.
  const ThreadPostRatingReceipt({required this.tid, required this.pid});

  /// Rated thread identity.
  final String tid;

  /// Rated post identity.
  final String pid;
}

/// Reads and validates the current server-side post-rating form.
abstract interface class ThreadPostRatingPreparationRepository {
  /// Capabilities proved by this source.
  ThreadPostRatingCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ThreadPostRatingPreparation, ThreadPostRatingCapabilities>
  >
  load(ThreadPostRatingPreparationRequest request);
}

/// Submits a rating through a previously prepared form.
abstract interface class ThreadPostRatingCommand {
  /// Capabilities proved by this source.
  ThreadPostRatingCapabilities get capabilities;

  /// Executes the command without exposing source payloads.
  Future<DataCommandResult<ThreadPostRatingReceipt>> execute(
    ThreadPostRatingSubmission submission,
  );
}

/// Business capabilities exposed while preparing or submitting a comment.
enum ThreadPostCommentCapability {
  /// The source proves the target thread and post identities.
  stablePostIdentity,

  /// The source provides the server's text-length limit.
  textLengthLimit,

  /// The source accepts plain-text post comments.
  plainTextComment,

  /// The source can submit a comment through an explicit command response.
  commandSubmission,
}

/// Fail-closed source capabilities for comment preparation and submission.
final class ThreadPostCommentCapabilities {
  /// Creates capabilities from explicit support values.
  const ThreadPostCommentCapabilities({required this.values});

  /// Support values for every known capability.
  final DataCapabilitySet<ThreadPostCommentCapability> values;

  /// Whether [capability] is explicitly supported.
  bool supports(ThreadPostCommentCapability capability) =>
      values.supports(capability);
}

/// Opaque proof that a comment form was prepared by a compatible adapter.
///
/// Applications must preserve this value unchanged and must not inspect it.
abstract interface class ThreadPostCommentPreparationToken {}

/// Requests the current comment form for one stable post.
final class ThreadPostCommentPreparationRequest {
  /// Creates a comment-form request.
  const ThreadPostCommentPreparationRequest({
    required this.tid,
    required this.pid,
    this.page = 1,
    this.referer,
    this.cancellation,
  });

  /// Stable thread identity.
  final String tid;

  /// Stable post identity.
  final String pid;

  /// Current thread page used by the Discuz floating form.
  final int page;

  /// Optional same-site page reference used as the HTTP Referer.
  final Uri? referer;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Source-neutral comment form prepared from the current server response.
final class ThreadPostCommentPreparation {
  /// Creates a prepared comment form.
  const ThreadPostCommentPreparation({
    required this.tid,
    required this.pid,
    required this.maxLength,
    required this.token,
  });

  /// Proven thread identity.
  final String tid;

  /// Proven post identity.
  final String pid;

  /// Maximum accepted text length, or zero when the source has no limit.
  final int maxLength;

  /// Opaque adapter proof required for safe submission.
  final ThreadPostCommentPreparationToken token;
}

/// User-entered comment submitted against one prepared form.
final class ThreadPostCommentSubmission {
  /// Creates a comment submission.
  const ThreadPostCommentSubmission({
    required this.preparation,
    required this.message,
    this.cancellation,
  });

  /// Prepared server form and opaque proof.
  final ThreadPostCommentPreparation preparation;

  /// User-entered plain-text comment.
  final String message;

  /// Optional caller-owned cancellation signal.
  final ForumRequestCancellation? cancellation;
}

/// Confirmed comment-command receipt that excludes server response payloads.
final class ThreadPostCommentReceipt {
  /// Creates a confirmed receipt.
  const ThreadPostCommentReceipt({required this.tid, required this.pid});

  /// Commented thread identity.
  final String tid;

  /// Commented post identity.
  final String pid;
}

/// Reads and validates the current server-side post-comment form.
abstract interface class ThreadPostCommentPreparationRepository {
  /// Capabilities proved by this source.
  ThreadPostCommentCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ThreadPostCommentPreparation, ThreadPostCommentCapabilities>
  >
  load(ThreadPostCommentPreparationRequest request);
}

/// Submits a comment through a previously prepared form.
abstract interface class ThreadPostCommentCommand {
  /// Capabilities proved by this source.
  ThreadPostCommentCapabilities get capabilities;

  /// Executes the command without exposing source payloads.
  Future<DataCommandResult<ThreadPostCommentReceipt>> execute(
    ThreadPostCommentSubmission submission,
  );
}
