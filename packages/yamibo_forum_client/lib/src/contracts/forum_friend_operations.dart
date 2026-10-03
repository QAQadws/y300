/// Native friendship forms and commands advertised by a profile toolbar.
library;

import '../network/forum_request.dart';
import 'data_command_contract.dart';
import 'data_read_contract.dart';
import 'profile_and_blog.dart';

/// The effect advertised by the fresh friendship form.
enum ForumFriendAction {
  /// Send a request that the recipient must approve.
  request,

  /// Accept an existing request from the target user.
  approve,

  /// Remove an existing friendship.
  remove,
}

/// Fresh-form query carrying the exact source-advertised destination.
final class ForumFriendQuery {
  /// Creates a friendship preparation query.
  const ForumFriendQuery({
    required this.actorUserId,
    required this.targetUserId,
    required this.actionLink,
    this.cancellation,
  });

  /// Expected signed-in account.
  final String actorUserId;

  /// Profile owner receiving the operation.
  final String targetUserId;

  /// Previously validated profile toolbar action.
  final ForumUserProfileActionLink actionLink;

  /// Optional caller cancellation.
  final ForumRequestCancellation? cancellation;
}

/// One source-defined friend group; its label remains source content.
final class ForumFriendGroup {
  /// Creates a friend group option.
  const ForumFriendGroup({required this.id, required this.name});

  /// Source group identifier.
  final String id;

  /// Source group name.
  final String name;
}

/// Opaque, short-lived, single-use form proof. Never persist or log it.
abstract interface class ForumFriendOperationToken {}

/// Complete source form projected into native editable values.
final class ForumFriendPreparation {
  /// Creates a friendship preparation.
  const ForumFriendPreparation({
    required this.actorUserId,
    required this.targetUserId,
    required this.action,
    required this.token,
    this.groups = const [],
    this.selectedGroupId,
    this.noteMaxLength = 30,
  });

  /// Proven signed-in actor.
  final String actorUserId;

  /// Proven target identity.
  final String targetUserId;

  /// Request, approval or removal determined from the actual form.
  final ForumFriendAction action;

  /// Adapter-owned, one-use proof.
  final ForumFriendOperationToken token;

  /// Advertised friend group options.
  final List<ForumFriendGroup> groups;

  /// Initial friend group from the form.
  final String? selectedGroupId;

  /// Maximum request-note length accepted by the supported source.
  final int noteMaxLength;

  /// Whether this form accepts a request note.
  bool get acceptsNote => action == ForumFriendAction.request;
}

/// Effective capabilities of one complete friendship form.
final class ForumFriendReadCapabilities {
  /// Creates form capabilities from the supported action.
  const ForumFriendReadCapabilities({required this.action});

  /// Proven form action.
  final ForumFriendAction action;
}

/// User-edited friendship form against one transient preparation.
final class ForumFriendSubmission {
  /// Creates a submission without exposing protected form fields.
  const ForumFriendSubmission({
    required this.preparation,
    required this.actorUserId,
    this.groupId,
    this.note = '',
    this.cancellation,
  });

  /// Prepared source form.
  final ForumFriendPreparation preparation;

  /// Current signed-in actor, verified again immediately before sending.
  final String actorUserId;

  /// A group from the preparation's advertised options.
  final String? groupId;

  /// Request note; valid only when the prepared form accepts it.
  final String note;

  /// Optional caller cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Confirmed server effect, without raw messages or response payloads.
final class ForumFriendReceipt {
  /// Creates a verified friendship receipt.
  const ForumFriendReceipt({
    required this.actorUserId,
    required this.targetUserId,
    required this.action,
  });

  /// Account that performed the operation.
  final String actorUserId;

  /// Target account.
  final String targetUserId;

  /// Confirmed effect; a request does not imply an accepted friendship.
  final ForumFriendAction action;
}

/// Native supported friendship preparation and single-attempt submission.
abstract interface class ForumFriendOperations {
  /// Loads and validates a fresh complete form.
  Future<DataReadResult<ForumFriendPreparation, ForumFriendReadCapabilities>>
  prepare(ForumFriendQuery query);

  /// Sends one prepared form; inconclusive outcomes must never auto-retry.
  Future<DataCommandResult<ForumFriendReceipt>> submit(
    ForumFriendSubmission submission,
  );
}
